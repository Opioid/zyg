const Layer = @import("../sample_base.zig").Layer;
const bxdf = @import("../bxdf.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const fresnel = @import("../fresnel.zig");
const ggx = @import("../ggx.zig");
const hlp = @import("../sample_helper.zig");
const inthlp = @import("../../../rendering/integrator/helper.zig");
const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

pub const Coating = struct {
    layer: Layer = undefined,

    absorption_coef: Vec4f = undefined,

    thickness: f32 = 0.0,
    ior: f32 = undefined,
    f0: f32 = undefined,
    alpha: f32 = undefined,
    weight: f32 = undefined,

    const Self = @This();

    pub const Result = struct {
        reflection: Vec4f,
        attenuation: Vec4f,
        f: f32,
        pdf: f32,
    };

    pub fn evaluate(self: Self, wi: Vec4f, wo: Vec4f, h: Vec4f, wo_dot_h: f32, avoid_caustics: bool) Result {
        const n_dot_wi = self.layer.clampNdot(wi);
        const n_dot_wo = self.layer.clampAbsNdot(wo);

        const att = self.attenuation(n_dot_wi, n_dot_wo);

        if (avoid_caustics and self.alpha <= ggx.Min_alpha) {
            return .{ .reflection = @splat(4, @as(f32, 0.0)), .attenuation = att, .f = 0.0, .pdf = 0.0 };
        }

        const n_dot_h = math.saturate(self.layer.nDot(h));

        const schlick = fresnel.Schlick.init(@splat(4, self.f0));

        var fresnel_result: Vec4f = undefined;
        const gg = ggx.Iso.reflectionF(
            n_dot_wi,
            n_dot_wo,
            wo_dot_h,
            n_dot_h,
            self.alpha,
            schlick,
            &fresnel_result,
        );

        const ep = ggx.ilmEpDielectric(n_dot_wo, self.alpha, self.ior);
        return .{
            .reflection = @splat(4, ep * self.weight * n_dot_wi) * gg.reflection,
            .attenuation = att,
            .f = fresnel_result[0],
            .pdf = gg.pdf(),
        };
    }

    pub fn reflect(
        self: Self,
        wo: Vec4f,
        h: Vec4f,
        n_dot_wo: f32,
        n_dot_h: f32,
        wi_dot_h: f32,
        wo_dot_h: f32,
        att: *Vec4f,
        result: *bxdf.Sample,
    ) void {
        const f = result.reflection;
        const n_dot_wi = ggx.Iso.reflectNoFresnel(
            wo,
            h,
            n_dot_wo,
            n_dot_h,
            wi_dot_h,
            wo_dot_h,
            self.alpha,
            self.layer,
            result,
        );

        att.* = self.attenuation(n_dot_wi, n_dot_wo);

        const ep = ggx.ilmEpDielectric(n_dot_wo, self.alpha, self.ior);
        result.reflection *= @splat(4, ep * self.weight * n_dot_wi) * f;
    }

    pub fn sample(self: Self, wo: Vec4f, sampler: *Sampler, rng: *RNG, n_dot_h: *f32, result: *bxdf.Sample) f32 {
        const xi = sampler.sample2D(rng, 1);
        const h = ggx.Aniso.sample(wo, @splat(2, self.alpha), xi, self.layer, n_dot_h);

        const wo_dot_h = hlp.clampDot(wo, h);
        const f = fresnel.schlick1(wo_dot_h, self.f0);

        result.reflection = @splat(4, f);
        result.h = h;
        result.h_dot_wi = wo_dot_h;

        return f;
    }

    pub fn singleAttenuationStatic(absorption_coef: Vec4f, thickness: f32, n_dot_wo: f32) Vec4f {
        const d = thickness * (1.0 / n_dot_wo);

        return inthlp.attenuation3(absorption_coef, d);
    }

    pub fn singleAttenuation(self: Self, n_dot_wo: f32) Vec4f {
        return singleAttenuationStatic(self.absorption_coef, self.thickness, n_dot_wo);
    }

    fn attenuation(self: Self, n_dot_wi: f32, n_dot_wo: f32) Vec4f {
        const f = self.weight * fresnel.schlick1(@minimum(n_dot_wi, n_dot_wo), self.f0);
        const d = self.thickness * (1.0 / n_dot_wi + 1.0 / n_dot_wo);

        const absorption = inthlp.attenuation3(self.absorption_coef, d);
        return @splat(4, 1.0 - f) * absorption;
    }
};
