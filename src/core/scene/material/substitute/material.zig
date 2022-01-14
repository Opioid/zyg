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
const ts = @import("../../../image/texture/sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const ccoef = @import("../collision_coefficients.zig");

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

const Coating = struct {
    normal_map: Texture = undefined,
    thickness_map: Texture = .{},

    absorption_coef: Vec4f = undefined,

    thickness: f32 = 0.0,
    ior: f32 = undefined,
    alpha: f32 = undefined,

    pub fn setAttenuation(self: *Coating, color: Vec4f, distance: f32) void {
        self.absorption_coef = ccoef.attenutionCoefficient(color, distance);
    }

    pub fn setRoughness(self: *Coating, roughness: f32) void {
        const r = ggx.clampRoughness(roughness);
        self.alpha = r * r;
    }
};

pub const Material = struct {
    super: Base,

    normal_map: Texture = undefined,
    surface_map: Texture = undefined,
    emission_map: Texture = undefined,

    color: Vec4f = undefined,
    checkers: Vec4f = @splat(4, @as(f32, 0.0)),

    alpha: Vec2f = undefined,

    anisotropy: f32 = undefined,
    rotation: f32 = undefined,
    metallic: f32 = undefined,
    emission_factor: f32 = undefined,
    thickness: f32 = undefined,
    attenuation_distance: f32 = undefined,
    transparency: f32 = undefined,

    coating: Coating = .{},

    pub fn init(sampler_key: ts.Key, two_sided: bool) Material {
        return .{ .super = Base.init(sampler_key, two_sided) };
    }

    pub fn commit(self: *Material) void {
        self.super.properties.set(.EmissionMap, self.emission_map.valid());
        self.super.properties.set(.Caustic, self.alpha[0] <= ggx.Min_alpha);
    }

    pub fn prepareSampling(self: Material, scene: Scene) Vec4f {
        if (self.emission_map.valid()) {
            return @splat(4, self.emission_factor) * self.emission_map.average_3(scene);
        }

        return @splat(4, self.emission_factor) * self.super.emission;
    }

    pub fn setRoughness(self: *Material, roughness: f32, anisotropy: f32) void {
        const r = ggx.clampRoughness(roughness);

        if (anisotropy > 0.0) {
            const rv = ggx.clampRoughness(roughness * (1.0 - anisotropy));
            self.alpha = .{ r * r, rv * rv };
        } else {
            self.alpha = @splat(2, r * r);
        }

        self.anisotropy = anisotropy;
    }

    pub fn setTranslucency(self: *Material, thickness: f32, attenuation_distance: f32) void {
        const transparent = thickness > 0.0;
        self.super.properties.orSet(.TwoSided, transparent);
        self.thickness = thickness;
        self.attenuation_distance = attenuation_distance;
        self.transparency = if (transparent) @exp(-thickness * (1.0 / attenuation_distance)) else 0.0;
    }

    pub fn setCheckers(self: *Material, color_a: Vec4f, color_b: Vec4f, scale: f32) void {
        self.color = color_a;
        self.checkers = Vec4f{ color_b[0], color_b[1], color_b[2], scale };
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: *Worker) Sample {
        if (rs.subsurface) {
            const g = self.super.volumetric_anisotropy;
            return .{ .Volumetric = Volumetric.init(wo, rs, g) };
        }

        const key = ts.resolveKey(self.super.sampler_key, rs.filter);

        const color = if (self.checkers[3] > 0.0) self.analyticCheckers(
            rs,
            key,
            worker.*,
        ) else if (self.super.color_map.valid()) ts.sample2D_3(
            key,
            self.super.color_map,
            rs.uv,
            worker.scene.*,
        ) else self.color;

        const ef = @splat(4, self.emission_factor);
        const radiance = if (self.emission_map.valid()) ef * ts.sample2D_3(
            key,
            self.emission_map,
            rs.uv,
            worker.scene.*,
        ) else ef * self.super.emission;

        var alpha: Vec2f = undefined;
        var metallic: f32 = undefined;

        const nc = self.surface_map.numChannels();
        if (nc >= 2) {
            const surface = ts.sample2D_2(key, self.surface_map, rs.uv, worker.scene.*);
            const r = ggx.mapRoughness(surface[0]);
            alpha = anisotropicAlpha(r, self.anisotropy);
            metallic = surface[1];
        } else if (1 == nc) {
            const r = ggx.mapRoughness(ts.sample2D_1(key, self.surface_map, rs.uv, worker.scene.*));
            alpha = anisotropicAlpha(r, self.anisotropy);
            metallic = self.metallic;
        } else {
            alpha = self.alpha;
            metallic = self.metallic;
        }

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
        const ior_outside = if (coating_thickness > 0.0) coating_ior else rs.ior();

        var result = Surface.init(
            rs,
            wo,
            color,
            radiance,
            alpha,
            ior,
            ior_outside,
            metallic,
            self.attenuation_distance > 0.0,
        );

        if (self.normal_map.valid()) {
            const n = hlp.sampleNormal(wo, rs, self.normal_map, key, worker.scene.*);
            result.super.layer.setNormal(n);
        } else {
            result.super.layer.setTangentFrame(rs.t, rs.b, rs.n);
        }

        if (self.rotation > 0.0) {
            result.super.layer.rotateTangenFrame(self.rotation);
        }

        const thickness = self.thickness;
        if (thickness > 0.0) {
            result.setTranslucency(color, thickness, self.attenuation_distance, self.transparency);
        }

        if (coating_thickness > 0.0) {
            if (self.normal_map.equal(self.coating.normal_map)) {
                result.coating.layer = result.super.layer;
            } else if (self.coating.normal_map.valid()) {
                const n = hlp.sampleNormal(wo, rs, self.coating.normal_map, key, worker.scene.*);
                result.coating.layer.setNormal(n);
            } else {
                result.coating.layer.setTangentFrame(rs.t, rs.b, rs.n);
            }

            result.coating.absorption_coef = self.coating.absorption_coef;
            result.coating.thickness = coating_thickness;
            result.coating.ior = coating_ior;
            result.coating.f0 = fresnel.Schlick.F0(coating_ior, rs.ior());
            result.coating.alpha = self.coating.alpha;
            result.coating.weight = coating_weight;

            const n_dot_wo = result.coating.layer.clampAbsNdot(wo);
            result.super.radiance *= result.coating.singleAttenuation(n_dot_wo);
        }

        return Sample{ .Substitute = result };
    }

    pub fn evaluateRadiance(
        self: Material,
        wi: Vec4f,
        n: Vec4f,
        uvw: Vec4f,
        filter: ?ts.Filter,
        worker: Worker,
    ) Vec4f {
        const key = ts.resolveKey(self.super.sampler_key, filter);
        const uv = Vec2f{ uvw[0], uvw[1] };

        const ef = @splat(4, self.emission_factor);
        const radiance = if (self.emission_map.valid())
            ef * ts.sample2D_3(key, self.emission_map, uv, worker.scene.*)
        else
            ef * self.super.emission;

        var coating_thickness: f32 = undefined;
        if (self.coating.thickness_map.valid()) {
            const relative_thickness = ts.sample2D_1(key, self.super.color_map, uv, worker.scene.*);
            coating_thickness = self.coating.thickness * relative_thickness;
        } else {
            coating_thickness = self.coating.thickness;
        }

        if (coating_thickness > 0.0) {
            const att = SampleCoating.singleAttenuationStatic(
                self.coating.absorption_coef,
                self.coating.thickness,
                hlp.clampAbsDot(wi, n),
            );

            return att * radiance;
        }

        return radiance;
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
