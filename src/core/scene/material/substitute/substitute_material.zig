const Base = @import("../material_base.zig").Base;
const SampleCoating = @import("substitute_coating.zig").Coating;
const hlp = @import("../material_helper.zig");
const ggx = @import("../ggx.zig");
const fresnel = @import("../fresnel.zig");
const Sample = @import("../material_sample.zig").Sample;
const Surface = @import("substitute_sample.zig").Sample;
const Volumetric = @import("../volumetric/volumetric_sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Emittance = @import("../../light/emittance.zig").Emittance;
const Worker = @import("../../../rendering/worker.zig").Worker;
const Scene = @import("../../scene.zig").Scene;
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const ts = @import("../../../image/texture/texture_sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const ccoef = @import("../collision_coefficients.zig");
const CC = ccoef.CC;

const base = @import("base");
const math = base.math;
const Frame = math.Frame;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

const Coating = struct {};

pub const Material = struct {
    super: Base = .{},

    emittance: Emittance = .{},

    color_map: Texture = Texture.initUniform3(@splat(0.5)),
    normal_map: Texture = .{},
    roughness_map: Texture = Texture.initUniform1(0.8),
    metallic_map: Texture = Texture.initUniform1(0.0),
    rotation_map: Texture = Texture.initUniform1(0.0),
    coating_normal_map: Texture = .{},
    coating_thickness_map: Texture = .{},
    coating_roughness_map: Texture = Texture.initUniform1(0.2),

    checkers: Vec4f = @splat(0.0),
    coating_absorption_coef: Vec4f = @splat(0.0),
    flakes_color: Vec4f = @splat(0.8),

    cc: CC = undefined,
    attenuation_distance: f32 = 0.0,
    ior: f32 = 1.46,
    anisotropy: f32 = 0.0,
    thickness: f32 = 0.0,
    transparency: f32 = 0.0,
    coating_thickness: f32 = 0.0,
    coating_ior: f32 = 1.5,
    flakes_coverage: f32 = 0.0,
    flakes_alpha: f32 = 0.01,
    flakes_res: f32 = 0.0,

    pub fn commit(self: *Material) void {
        const properties = &self.super.properties;

        properties.evaluate_visibility = self.super.mask.valid();
        properties.emissive = math.anyGreaterZero3(self.emittance.value);
        properties.color_map = self.color_map.valid() or self.checkers[3] > 0.0;
        properties.emission_map = self.emittance.emission_map.valid();
        properties.caustic = !self.roughness_map.valid() and self.roughness_map.uniform1() <= ggx.MinRoughness;

        const thickness = self.thickness;
        const transparent = thickness > 0.0;
        const attenuation_distance = self.attenuation_distance;
        properties.two_sided = properties.two_sided or transparent;
        self.transparency = if (transparent) @exp(-thickness * (1.0 / attenuation_distance)) else 0.0;

        properties.dense_sss_optimization = attenuation_distance <= 0.1 and properties.scattering_volume;

        // This doesn't make a difference for shading, but is intended for the Albedo AOV...
        if (properties.dense_sss_optimization and !self.color_map.valid()) {
            const cc = self.cc;

            const mu_t = cc.a + cc.s;
            const albedo = cc.s / mu_t;
            self.color_map = Texture.initUniform3(albedo);
        }
    }

    pub fn setVolumetric(
        self: *Material,
        attenuation_color: Vec4f,
        subsurface_color: Vec4f,
        distance: f32,
        anisotropy: f32,
    ) void {
        const aniso = math.clamp(anisotropy, -0.999, 0.999);
        const cc = ccoef.attenuation(attenuation_color, subsurface_color, distance, aniso);

        self.cc = cc;
        self.attenuation_distance = distance;
        self.super.properties.scattering_volume = math.anyGreaterZero3(cc.s);
    }

    pub fn prepareSampling(self: *const Material, area: f32, scene: *const Scene) Vec4f {
        const rad = self.emittance.averageRadiance(area);
        if (self.emittance.emission_map.valid()) {
            return rad * self.emittance.emission_map.average_3(scene);
        }

        return rad;
    }

    pub fn setColor(self: *Material, color: Base.MappedValue(Vec4f)) void {
        self.color_map = color.flatten();
    }

    pub fn setRoughness(self: *Material, roughness: Base.MappedValue(f32)) void {
        self.roughness_map = roughness.flatten();
    }

    pub fn setMetallic(self: *Material, metallic: Base.MappedValue(f32)) void {
        self.metallic_map = metallic.flatten();
    }

    pub fn setRotation(self: *Material, rotation: Base.MappedValue(f32)) void {
        self.rotation_map = rotation.flatten();
    }

    pub fn setCheckers(self: *Material, color_a: Vec4f, color_b: Vec4f, scale: f32) void {
        self.color_map = Texture.initUniform3(color_a);
        self.checkers = Vec4f{ color_b[0], color_b[1], color_b[2], scale };
    }

    pub fn setCoatingAttenuation(self: *Material, color: Vec4f, distance: f32) void {
        self.coating_absorption_coef = ccoef.attenuationCoefficient(color, distance);
    }

    pub fn setCoatingThickness(self: *Material, thickness: Base.MappedValue(f32)) void {
        self.coating_thickness_map = thickness.texture;
        self.coating_thickness = thickness.value;
    }

    pub fn setCoatingRoughness(self: *Material, roughness: Base.MappedValue(f32)) void {
        self.coating_roughness_map = roughness.flatten();
    }

    pub fn setFlakesRoughness(self: *Material, roughness: f32) void {
        const r = ggx.clampRoughness(roughness);
        self.flakes_alpha = r * r;
    }

    pub fn setFlakesSize(self: *Material, size: f32) void {
        const N = 1.5396 / (size * size);
        const K = 4.0;

        self.flakes_res = math.max(4.0, @ceil(@sqrt(N / K)));
    }

    pub fn sample(self: *const Material, wo: Vec4f, rs: Renderstate, sampler: *Sampler, worker: *const Worker) Sample {
        if (rs.volumeScatter()) {
            const g = self.cc.anisotropy();
            return .{ .Volumetric = Volumetric.init(wo, rs, g) };
        }

        const key = self.super.sampler_key;

        const color = if (self.checkers[3] > 0.0) self.analyticCheckers(
            rs,
            key,
            worker,
        ) else ts.sample2D_3(key, self.color_map, rs.uv, sampler, worker.scene);

        const roughness = ggx.clampRoughness(ts.sample2D_1(key, self.roughness_map, rs.uv, sampler, worker.scene));
        const metallic = ts.sample2D_1(key, self.metallic_map, rs.uv, sampler, worker.scene);

        const alpha = anisotropicAlpha(roughness, self.anisotropy);

        var coating_thickness: f32 = undefined;
        var coating_weight: f32 = undefined;
        var coating_ior: f32 = undefined;
        if (self.coating_thickness_map.valid()) {
            const relative_thickness = ts.sample2D_1(key, self.coating_thickness_map, rs.uv, sampler, worker.scene);
            coating_thickness = self.coating_thickness * relative_thickness;
            coating_weight = if (relative_thickness > 0.1) 1.0 else relative_thickness;
            coating_ior = math.lerp(rs.ior, self.coating_ior, coating_weight);
        } else {
            coating_thickness = self.coating_thickness;
            coating_weight = 1.0;
            coating_ior = self.coating_ior;
        }

        const ior = self.ior;
        const ior_outer = if (coating_thickness > 0.0) coating_ior else rs.ior;
        const attenuation_distance = self.attenuation_distance;

        var result = Surface.init(
            rs,
            wo,
            color,
            alpha,
            ior,
            ior_outer,
            rs.ior,
            metallic,
            attenuation_distance > 0.0,
            self.super.priority,
        );

        if (self.normal_map.valid()) {
            const n = hlp.sampleNormal(wo, rs, self.normal_map, key, sampler, worker.scene);
            result.super.frame = Frame.init(n);
        } else {
            result.super.frame = .{ .x = rs.t, .y = rs.b, .z = rs.n };
        }

        const thickness = self.thickness;
        if (thickness > 0.0) {
            result.setTranslucency(color, thickness, attenuation_distance, self.transparency);
        }

        if (coating_thickness > 0.0) {
            if (self.normal_map.equal(self.coating_normal_map)) {
                result.coating.n = result.super.frame.z;
            } else if (self.coating_normal_map.valid()) {
                const n = hlp.sampleNormal(wo, rs, self.coating_normal_map, key, sampler, worker.scene);
                result.coating.n = n;
            } else {
                result.coating.n = rs.n;
            }

            const r = ggx.clampRoughness(ts.sample2D_1(key, self.coating_roughness_map, rs.uv, sampler, worker.scene));

            result.coating.absorption_coef = self.coating_absorption_coef;
            result.coating.thickness = coating_thickness;
            result.coating.f0 = fresnel.Schlick.IorToF0(coating_ior, rs.ior);
            result.coating.alpha = r * r;
            result.coating.weight = coating_weight;
        }

        // Apply rotation to base frame after coating is calculated, so that coating is not affected
        const rotation = ts.sample2D_1(key, self.rotation_map, rs.uv, sampler, worker.scene) * (2.0 * std.math.pi);

        if (rotation > 0.0) {
            result.super.frame.rotateTangenFrame(rotation);
        }

        const flakes_coverage = self.flakes_coverage;
        if (flakes_coverage > 0.0) {
            const op = rs.trafo.worldToObjectNormal(rs.p - rs.trafo.position);
            const on = rs.trafo.worldToObjectNormal(result.super.frame.z);

            const uv = hlp.triplanarMapping(op, on);

            const flake = sampleFlake(uv, self.flakes_res, flakes_coverage);

            if (flake) |xi| {
                const fa = self.flakes_alpha;
                const a2_cone = flakesA2cone(fa);
                const fa2 = fa - a2_cone;
                const cos_cone = 1.0 - (2.0 * a2_cone) / (1.0 + a2_cone);

                var n_dot_h: f32 = undefined;
                const m = ggx.Aniso.sample(wo, @splat(fa2), xi, result.super.frame, &n_dot_h);

                result.metallic = 1.0;
                result.f0 = self.flakes_color;
                result.super.alpha = .{ cos_cone, a2_cone };
                result.super.frame = Frame.init(m);

                result.super.properties.flakes = true;
            }
        }

        result.super.properties.exit_sss = rs.exitSSS();
        result.super.properties.dense_sss_optimization = self.super.properties.dense_sss_optimization;

        return Sample{ .Substitute = result };
    }

    fn flakesA2cone(alpha: f32) f32 {
        const target_angle = comptime math.solidAngleOfCone(@cos(math.degreesToRadians(7.0)));
        const limit = comptime target_angle / ((4.0 * std.math.pi) - target_angle);

        return math.min(limit, 0.5 * alpha);
    }

    fn gridCell(uv: Vec2f, res: f32) Vec2i {
        const i: i32 = @intFromFloat(res * @mod(uv[0], 1.0));
        const j: i32 = @intFromFloat(res * @mod(uv[1], 1.0));
        return .{ i, j };
    }

    fn sampleFlake(uv: Vec2f, res: f32, coverage: f32) ?Vec2f {
        const ij = gridCell(uv, res);
        const suv = @as(Vec2f, @splat(res)) * uv;

        var nearest_d: f32 = std.math.floatMax(f32);
        var nearest_r: f32 = undefined;
        var nearest_xi: Vec2f = undefined;

        var ii = ij[0] - 1;
        while (ii <= ij[0] + 1) : (ii += 1) {
            var jj = ij[1] - 1;
            while (jj <= ij[1] + 1) : (jj += 1) {
                const fij = Vec2f{ @floatFromInt(ii), @floatFromInt(jj) };

                var rng = base.rnd.SingleGenerator.init(fuse(ii, jj));

                var fl: u32 = 0;
                while (fl < 4) : (fl += 1) {
                    const p = fij + Vec2f{ rng.randomFloat(), rng.randomFloat() };
                    const xi = Vec2f{ rng.randomFloat(), rng.randomFloat() };
                    const r = rng.randomFloat();

                    const vcd = math.squaredLength2(suv - p);
                    if (vcd < nearest_d) {
                        nearest_d = vcd;
                        nearest_r = r;
                        nearest_xi = xi;
                    }
                }
            }
        }

        return if (nearest_r < coverage) nearest_xi else null;
    }

    fn fuse(a: i32, b: i32) u64 {
        return (@as(u64, @as(u32, @bitCast(a))) << 32) | @as(u64, @as(u32, @bitCast(b)));
    }

    pub fn evaluateRadiance(
        self: *const Material,
        p: Vec4f,
        wi: Vec4f,
        n: Vec4f,
        uv: Vec2f,
        trafo: Trafo,
        prop: u32,
        part: u32,
        sampler: *Sampler,
        scene: *const Scene,
    ) Vec4f {
        const key = self.super.sampler_key;

        const rad = self.emittance.radiance(p, wi, uv, trafo, prop, part, key, sampler, scene);

        var coating_thickness: f32 = undefined;
        if (self.coating_thickness_map.valid()) {
            const relative_thickness = ts.sample2D_1(key, self.color_map, uv, sampler, scene);
            coating_thickness = self.coating_thickness * relative_thickness;
        } else {
            coating_thickness = self.coating_thickness;
        }

        if (coating_thickness > 0.0) {
            const n_dot_wi = math.safe.clampAbsDot(wi, n);
            const att = SampleCoating.singleAttenuationStatic(
                self.coating_absorption_coef,
                coating_thickness,
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

        return @splat(r * r);
    }

    // https://www.iquilezles.org/www/articles/checkerfiltering/checkerfiltering.htm

    fn analyticCheckers(self: *const Material, rs: Renderstate, sampler_key: ts.Key, worker: *const Worker) Vec4f {
        const checkers_scale = self.checkers[3];

        const dd = @as(Vec4f, @splat(checkers_scale)) * worker.screenspaceDifferential(rs);

        const t = checkersGrad(
            @as(Vec2f, @splat(checkers_scale)) * sampler_key.address.address2(rs.uv),
            .{ dd[0], dd[1] },
            .{ dd[2], dd[3] },
        );

        return math.lerp(self.color_map.uniform3(), self.checkers, @as(Vec4f, @splat(t)));
    }

    fn checkersGrad(uv: Vec2f, ddx: Vec2f, ddy: Vec2f) f32 {
        // filter kernel
        const w = math.max2(@abs(ddx), @abs(ddy)) + @as(Vec2f, @splat(0.0001));

        // analytical integral (box filter)
        const i = (tri(uv + @as(Vec2f, @splat(0.5)) * w) - tri(uv - @as(Vec2f, @splat(0.5)) * w)) / w;

        // xor pattern
        return 0.5 - 0.5 * i[0] * i[1];
    }

    // triangular signal
    fn tri(x: Vec2f) Vec2f {
        const hx = math.frac(x[0] * 0.5) - 0.5;
        const hy = math.frac(x[1] * 0.5) - 0.5;
        return .{ 1.0 - 2.0 * @abs(hx), 1.0 - 2.0 * @abs(hy) };
    }
};
