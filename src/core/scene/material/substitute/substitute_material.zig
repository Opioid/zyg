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
const Context = @import("../../context.zig").Context;
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

    color: Texture = Texture.initUniform3(@splat(0.5)),
    normal_map: Texture = Texture.initUniform1(0.0),
    roughness: Texture = Texture.initUniform1(0.8),
    metallic: Texture = Texture.initUniform1(0.0),
    specular: Texture = Texture.initUniform1(1.0),
    rotation: Texture = Texture.initUniform1(0.0),
    translucency: Texture = Texture.initUniform1(0.0),
    attenuation_color: Texture = Texture.initUniform3(@splat(0.0)),
    coating_normal_map: Texture = Texture.initUniform1(0.0),
    coating_scale: Texture = Texture.initUniform1(1.0),
    coating_roughness: Texture = Texture.initUniform1(0.2),
    flakes_coverage: Texture = Texture.initUniform1(0.0),

    coating_absorption_coef: Vec4f = @splat(0.0),
    flakes_color: Vec4f = @splat(0.8),

    attenuation_distance: f32 = 0.0,
    ior: f32 = 1.46,
    anisotropy: f32 = 0.0,
    volumetric_anisotropy: f32 = 0.0,
    coating_thickness: f32 = 0.0,
    coating_ior: f32 = 1.5,
    flakes_alpha: f32 = 0.01,
    flakes_res: f32 = 0.0,

    pub fn commit(self: *Material) void {
        const properties = &self.super.properties;

        properties.evaluate_visibility = self.super.mask.isImage();
        properties.emissive = math.anyGreaterZero3(self.emittance.value);
        properties.color_map = !self.color.isUniform();
        properties.emission_image_map = self.emittance.emission_map.isImage();
        properties.caustic = self.roughness.isUniform() and self.roughness.uniform1() <= ggx.MinRoughness;

        const attenuation_distance = self.attenuation_distance;

        properties.scattering_volume = attenuation_distance > 0.0 and (!self.color.isUniform() or math.anyGreaterZero3(self.color.uniform3()));
        properties.dense_sss_optimization = attenuation_distance <= 0.1 and properties.scattering_volume;
    }

    pub fn setVolumetricAnisotropy(self: *Material, anisotropy: f32) void {
        self.volumetric_anisotropy = math.clamp(anisotropy, -0.999, 0.999);
    }

    pub fn setCoatingAttenuation(self: *Material, color: Vec4f, distance: f32) void {
        self.coating_absorption_coef = ccoef.attenuationCoefficient(color, distance);
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

    pub fn prepareSampling(self: *const Material, area: f32, scene: *const Scene) Vec4f {
        const rad = self.emittance.averageRadiance(area);
        if (!self.emittance.emission_map.isUniform()) {
            return rad * self.emittance.emission_map.average_3(scene);
        }

        return rad;
    }

    pub fn sample(self: *const Material, wo: Vec4f, rs: Renderstate, sampler: *Sampler, context: Context) Sample {
        if (rs.volumeScatter()) {
            const g = self.volumetric_anisotropy;
            return .{ .Volumetric = Volumetric.init(wo, rs, g) };
        }

        const color = ts.sample2D_3(self.color, rs, sampler, context);

        const roughness = ggx.clampRoughness(ts.sample2D_1(self.roughness, rs, sampler, context));
        const metallic = ts.sample2D_1(self.metallic, rs, sampler, context);
        const specular = ts.sample2D_1(self.specular, rs, sampler, context);

        const alpha = anisotropicAlpha(roughness, self.anisotropy);

        const coating_scale = ts.sample2D_1(self.coating_scale, rs, sampler, context);
        const coating_thickness = coating_scale * self.coating_thickness;
        const coating_weight = if (coating_scale > 0.1) 1.0 else coating_scale;
        const coating_ior = math.lerp(rs.ior, self.coating_ior, coating_weight);

        const ior = self.ior;
        const ior_outer = if (coating_thickness > 0.0) coating_ior else rs.ior;
        const attenuation_distance = self.attenuation_distance;
        const attenuation_color = ts.sample2D_3(self.attenuation_color, rs, sampler, context);

        const translucency = ts.sample2D_1(self.translucency, rs, sampler, context);

        var result = Surface.init(
            rs,
            wo,
            color,
            attenuation_color,
            alpha,
            ior,
            ior_outer,
            rs.ior,
            metallic,
            specular,
            attenuation_distance,
            self.volumetric_anisotropy,
            translucency,
            self.super.priority,
        );

        if (!self.normal_map.isUniform()) {
            const n = hlp.sampleNormal(wo, rs, self.normal_map, sampler, context);
            result.super.frame = Frame.init(n);
        } else {
            result.super.frame = .{ .x = rs.t, .y = rs.b, .z = rs.n };
        }

        if (coating_thickness > 0.0) {
            if (self.normal_map.equal(self.coating_normal_map)) {
                result.coating.n = result.super.frame.z;
            } else if (!self.coating_normal_map.isUniform()) {
                const n = hlp.sampleNormal(wo, rs, self.coating_normal_map, sampler, context);
                result.coating.n = n;
            } else {
                result.coating.n = rs.n;
            }

            const r = ggx.clampRoughness(ts.sample2D_1(self.coating_roughness, rs, sampler, context));

            result.coating.absorption_coef = self.coating_absorption_coef;
            result.coating.thickness = coating_thickness;
            result.coating.f0 = fresnel.Schlick.IorToF0(coating_ior, rs.ior);
            result.coating.alpha = r * r;
            result.coating.weight = coating_weight;
        }

        // Apply rotation to base frame after coating is calculated, so that coating is not affected
        const rotation = ts.sample2D_1(self.rotation, rs, sampler, context) * (2.0 * std.math.pi);

        if (rotation > 0.0) {
            result.super.frame.rotateTangenFrame(rotation);
        }

        const flakes_coverage = ts.sample2D_1(self.flakes_coverage, rs, sampler, context);
        if (flakes_coverage > 0.0) {
            const op = rs.trafo.worldToObjectNormal(rs.p - rs.trafo.position);
            const on = rs.trafo.worldToObjectNormal(result.super.frame.z);

            const uv = math.frac(hlp.triplanarMapping(op, on));

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

    pub fn evaluateRadiance(self: *const Material, wi: Vec4f, rs: Renderstate, sampler: *Sampler, context: Context) Vec4f {
        const rad = self.emittance.radiance(wi, rs, sampler, context);

        const coating_scale = ts.sample2D_1(self.coating_scale, rs, sampler, context);
        const coating_thickness = coating_scale * self.coating_thickness;

        if (coating_thickness > 0.0) {
            const n_dot_wi = math.safe.clampAbsDot(wi, rs.geo_n);
            const att = SampleCoating.singleAttenuationStatic(self.coating_absorption_coef, coating_thickness, n_dot_wi);

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
};
