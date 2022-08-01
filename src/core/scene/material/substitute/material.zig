const Base = @import("../material_base.zig").Base;
const SampleCoating = @import("coating.zig").Coating;
const hlp = @import("../material_helper.zig");
const ggx = @import("../ggx.zig");
const fresnel = @import("../fresnel.zig");
const Sample = @import("../sample.zig").Sample;
const Surface = @import("sample.zig").Sample;
const Volumetric = @import("../volumetric/sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Worker = @import("../../worker.zig").Worker;
const Scene = @import("../../scene.zig").Scene;
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const ts = @import("../../../image/texture/sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const ccoef = @import("../collision_coefficients.zig");

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

const Coating = struct {
    normal_map: Texture = .{},
    thickness_map: Texture = .{},
    roughness_map: Texture = .{},

    absorption_coef: Vec4f = @splat(4, @as(f32, 0.0)),

    thickness: f32 = 0.0,
    ior: f32 = 1.5,
    roughness: f32 = 0.2,

    pub fn setAttenuation(self: *Coating, color: Vec4f, distance: f32) void {
        self.absorption_coef = ccoef.attenuationCoefficient(color, distance);
    }

    pub fn setThickness(self: *Coating, thickness: Base.MappedValue(f32)) void {
        self.thickness_map = thickness.texture;
        self.thickness = thickness.value;
    }

    pub fn setRoughness(self: *Coating, roughness: Base.MappedValue(f32)) void {
        self.roughness_map = roughness.texture;
        self.roughness = ggx.clampRoughness(roughness.value);
    }
};

pub const Material = struct {
    super: Base = .{},

    normal_map: Texture = .{},
    surface_map: Texture = .{},
    rotation_map: Texture = .{},
    emission_map: Texture = .{},

    color: Vec4f = @splat(4, @as(f32, 0.5)),
    checkers: Vec4f = @splat(4, @as(f32, 0.0)),

    roughness: f32 = 0.8,
    anisotropy: f32 = 0.0,
    rotation: f32 = 0.0,
    metallic: f32 = 0.0,
    thickness: f32 = 0.0,
    transparency: f32 = 0.0,

    coating: Coating = .{},

    pub fn commit(self: *Material) void {
        self.super.properties.set(.EmissionMap, self.emission_map.valid());
        self.super.properties.set(.Caustic, self.roughness <= ggx.Min_roughness);

        const thickness = self.thickness;
        const transparent = thickness > 0.0;
        const attenuation_distance = self.super.attenuation_distance;
        self.super.properties.orSet(.TwoSided, transparent);
        self.transparency = if (transparent) @exp(-thickness * (1.0 / attenuation_distance)) else 0.0;
    }

    pub fn prepareSampling(self: Material, area: f32, scene: Scene) Vec4f {
        const rad = self.super.emittance.averageRadiance(area);
        if (self.emission_map.valid()) {
            return rad * self.emission_map.average_3(scene);
        }

        return rad;
    }

    pub fn setColor(self: *Material, color: Base.MappedValue(Vec4f)) void {
        self.super.color_map = color.texture;
        self.color = color.value;
    }

    pub fn setRoughness(self: *Material, roughness: Base.MappedValue(f32)) void {
        self.surface_map = roughness.texture;
        const r = roughness.value;
        self.roughness = ggx.clampRoughness(r);
    }

    pub fn setRotation(self: *Material, rotation: Base.MappedValue(f32)) void {
        self.rotation_map = rotation.texture;
        self.rotation = rotation.value * (2.0 * std.math.pi);
    }

    pub fn setCheckers(self: *Material, color_a: Vec4f, color_b: Vec4f, scale: f32) void {
        self.color = color_a;
        self.checkers = Vec4f{ color_b[0], color_b[1], color_b[2], scale };
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: Worker) Sample {
        if (rs.subsurface) {
            const g = self.super.volumetric_anisotropy;
            return .{ .Volumetric = Volumetric.init(wo, rs, g) };
        }

        const key = ts.resolveKey(self.super.sampler_key, rs.filter);

        const color = if (self.checkers[3] > 0.0) self.analyticCheckers(
            rs,
            key,
            worker,
        ) else if (self.super.color_map.valid()) ts.sample2D_3(
            key,
            self.super.color_map,
            rs.uv,
            worker.scene.*,
        ) else self.color;

        var rad = self.super.emittance.radiance(
            -wo,
            rs.t,
            rs.b,
            rs.geo_n,
            worker.scene.lightArea(rs.prop, rs.part),
            rs.filter,
            worker.scene.*,
        );
        if (self.emission_map.valid()) {
            rad *= ts.sample2D_3(key, self.emission_map, rs.uv, worker.scene.*);
        }

        var roughness: f32 = undefined;
        var metallic: f32 = undefined;

        const nc = self.surface_map.numChannels();
        if (nc >= 2) {
            const surface = ts.sample2D_2(key, self.surface_map, rs.uv, worker.scene.*);
            roughness = ggx.mapRoughness(surface[0]);
            metallic = surface[1];
        } else if (1 == nc) {
            roughness = ggx.mapRoughness(ts.sample2D_1(key, self.surface_map, rs.uv, worker.scene.*));
            metallic = self.metallic;
        } else {
            roughness = self.roughness;
            metallic = self.metallic;
        }

        const alpha = anisotropicAlpha(roughness, self.anisotropy);

        var coating_thickness: f32 = undefined;
        var coating_weight: f32 = undefined;
        var coating_ior: f32 = undefined;
        if (self.coating.thickness_map.valid()) {
            const relative_thickness = ts.sample2D_1(key, self.super.color_map, rs.uv, worker.scene.*);
            coating_thickness = self.coating.thickness * relative_thickness;
            coating_weight = if (relative_thickness > 0.1) 1.0 else relative_thickness;
            coating_ior = math.lerp(rs.ior(), self.coating.ior, coating_weight);
        } else {
            coating_thickness = self.coating.thickness;
            coating_weight = 1.0;
            coating_ior = self.coating.ior;
        }

        const ior = self.super.ior;
        const ior_outer = if (coating_thickness > 0.0) coating_ior else rs.ior();
        const attenuation_distance = self.super.attenuation_distance;

        var result = Surface.init(
            rs,
            wo,
            color,
            rad,
            alpha,
            ior,
            ior_outer,
            rs.ior(),
            metallic,
            attenuation_distance > 0.0,
        );

        if (self.normal_map.valid()) {
            const n = hlp.sampleNormal(wo, rs, self.normal_map, key, worker.scene.*);
            result.super.frame.setNormal(n);
        } else {
            result.super.frame.setTangentFrame(rs.t, rs.b, rs.n);
        }

        const thickness = self.thickness;
        if (thickness > 0.0) {
            result.setTranslucency(color, thickness, attenuation_distance, self.transparency);
        }

        if (coating_thickness > 0.0) {
            if (self.normal_map.equal(self.coating.normal_map)) {
                result.coating.frame = result.super.frame;
            } else if (self.coating.normal_map.valid()) {
                const n = hlp.sampleNormal(wo, rs, self.coating.normal_map, key, worker.scene.*);
                result.coating.frame.setNormal(n);
            } else {
                result.coating.frame.setTangentFrame(rs.t, rs.b, rs.n);
            }

            const r = if (self.coating.roughness_map.valid())
                ggx.mapRoughness(ts.sample2D_1(key, self.coating.roughness_map, rs.uv, worker.scene.*))
            else
                self.coating.roughness;

            result.coating.absorption_coef = self.coating.absorption_coef;
            result.coating.thickness = coating_thickness;
            result.coating.ior = coating_ior;
            result.coating.f0 = fresnel.Schlick.F0(coating_ior, rs.ior());
            result.coating.alpha = r * r;
            result.coating.weight = coating_weight;

            const n_dot_wo = result.coating.frame.clampAbsNdot(wo);
            result.super.radiance *= result.coating.singleAttenuation(n_dot_wo);
        }

        // Apply rotation to base frame after coating is calculated, so that coating is not affected
        const rotation = if (self.rotation_map.valid())
            ts.sample2D_1(key, self.rotation_map, rs.uv, worker.scene.*) * (2.0 * std.math.pi)
        else
            self.rotation;

        if (rotation > 0.0) {
            result.super.frame.rotateTangenFrame(rotation);
        }

        return Sample{ .Substitute = result };
    }

    pub fn evaluateRadiance(
        self: Material,
        wi: Vec4f,
        n: Vec4f,
        uv: Vec2f,
        trafo: Trafo,
        extent: f32,
        filter: ?ts.Filter,
        scene: Scene,
    ) Vec4f {
        const key = ts.resolveKey(self.super.sampler_key, filter);

        var rad = self.super.emittance.radiance(wi, trafo, extent, filter, scene);
        if (self.emission_map.valid()) {
            rad *= ts.sample2D_3(key, self.emission_map, uv, scene);
        }

        var coating_thickness: f32 = undefined;
        if (self.coating.thickness_map.valid()) {
            const relative_thickness = ts.sample2D_1(key, self.super.color_map, uv, scene);
            coating_thickness = self.coating.thickness * relative_thickness;
        } else {
            coating_thickness = self.coating.thickness;
        }

        if (coating_thickness > 0.0) {
            const n_dot_wi = hlp.clampAbsDot(wi, n);
            const att = SampleCoating.singleAttenuationStatic(
                self.coating.absorption_coef,
                self.coating.thickness,
                n_dot_wi,
            );

            return att * rad;
        }

        return rad;
    }

    fn anisotropicAlpha(r: f32, anisotropy: f32) Vec2f {
        if (anisotropy > 0.0) {
            const rv = ggx.clampRoughness(r * (1.0 - anisotropy));
            return .{ r * r, rv * rv };
        }

        return @splat(2, r * r);
    }

    // https://www.iquilezles.org/www/articles/checkerfiltering/checkerfiltering.htm

    fn analyticCheckers(self: Material, rs: Renderstate, sampler_key: ts.Key, worker: Worker) Vec4f {
        const checkers_scale = self.checkers[3];

        const dd = @splat(4, checkers_scale) * worker.screenspaceDifferential(rs);

        const t = checkersGrad(
            @splat(2, checkers_scale) * sampler_key.address.address2(rs.uv),
            .{ dd[0], dd[1] },
            .{ dd[2], dd[3] },
        );

        return math.lerp3(self.color, self.checkers, t);
    }

    fn checkersGrad(uv: Vec2f, ddx: Vec2f, ddy: Vec2f) f32 {
        // filter kernel
        const w = @maximum(@fabs(ddx), @fabs(ddy)) + @splat(2, @as(f32, 0.0001));

        // analytical integral (box filter)
        const i = (tri(uv + @splat(2, @as(f32, 0.5)) * w) - tri(uv - @splat(2, @as(f32, 0.5)) * w)) / w;

        // xor pattern
        return 0.5 - 0.5 * i[0] * i[1];
    }

    // triangular signal
    fn tri(x: Vec2f) Vec2f {
        const hx = math.frac(x[0] * 0.5) - 0.5;
        const hy = math.frac(x[1] * 0.5) - 0.5;
        return .{ 1.0 - 2.0 * @fabs(hx), 1.0 - 2.0 * @fabs(hy) };
    }
};
