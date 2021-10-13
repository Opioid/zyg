const sample = @import("../sample_base.zig");
const Base = sample.SampleBase;
const IoR = sample.IoR;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const fresnel = @import("../fresnel.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const hlp = @import("../sample_helper.zig");
const inthlp = @import("../../../rendering/integrator/helper.zig");
const ggx = @import("../ggx.zig");
const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");

pub const Sample = struct {
    super: Base,

    absorption_coef: Vec4f,
    ior: f32,
    ior_outside: f32,
    f0: f32,
    thickness: f32,

    pub fn init(
        rs: Renderstate,
        wo: Vec4f,
        absorption_coef: Vec4f,
        ior: f32,
        ior_outside: f32,
        alpha: f32,
        thickness: f32,
    ) Sample {
        var super = Base.init(
            rs,
            wo,
            @splat(4, @as(f32, 1.0)),
            @splat(4, @as(f32, 0.0)),
            @splat(2, alpha),
        );

        const rough = alpha > 0.0;

        super.properties.set(.CanEvaluate, rough and ior != ior_outside);
        super.properties.set(.Translucent, thickness > 0.0);

        return .{
            .super = super,
            .absorption_coef = absorption_coef,
            .ior = ior,
            .ior_outside = ior_outside,
            .f0 = if (rough) fresnel.Schlick.F0(ior, ior_outside) else 0.0,
            .thickness = thickness,
        };
    }

    pub fn evaluate(self: Sample, wi: Vec4f) bxdf.Result {
        const alpha = self.super.alpha[0];
        const rough = alpha > 0.0;

        if (self.ior == self.ior_outside or !rough or
            (self.super.avoidCaustics() and alpha <= ggx.Min_alpha))
        {
            return bxdf.Result.init(@splat(4, @as(f32, 0.0)), 0.0);
        }

        const wo = self.super.wo;
        if (!self.super.sameHemisphere(wo)) {
            const quo_ior = IoR{ .eta_i = self.ior_outside, .eta_t = self.ior };
            const ior = quo_ior.swapped(false);

            const h = -math.normalize3(@splat(4, ior.eta_t) * wi + @splat(4, ior.eta_i) * wo);

            const wi_dot_h = math.dot3(wi, h);
            if (wi_dot_h <= 0.0) {
                return bxdf.Result.init(@splat(4, @as(f32, 0.0)), 0.0);
            }

            const wo_dot_h = math.dot3(wo, h);
            const eta = ior.eta_i / ior.eta_t;
            const sint2 = (eta * eta) * (1.0 - wo_dot_h * wo_dot_h);

            if (sint2 >= 1.0) {
                return bxdf.Result.init(@splat(4, @as(f32, 0.0)), 0.0);
            }

            const n_dot_wi = self.super.layer.clampNdot(wi);
            const n_dot_wo = self.super.layer.clampAbsNdot(wo);
            const n_dot_h = math.saturate(self.super.layer.nDot(h));

            const schlick = fresnel.Schlick1.init(self.f0);

            const gg = ggx.Iso.refraction(
                n_dot_wi,
                n_dot_wo,
                wi_dot_h,
                wo_dot_h,
                n_dot_h,
                alpha,
                ior,
                schlick,
            );

            const comp = ggx.ilmEpDielectric(n_dot_wo, alpha, self.ior);

            return bxdf.Result.init(
                @splat(4, std.math.min(n_dot_wi, n_dot_wo) * comp) * self.super.albedo * gg.reflection,
                gg.pdf(),
            );
        } else {
            const n_dot_wi = self.super.layer.clampNdot(wi);
            const n_dot_wo = self.super.layer.clampAbsNdot(wo);

            const h = math.normalize3(wo + wi);

            const wo_dot_h = hlp.clampDot(wo, h);
            const n_dot_h = math.saturate(self.super.layer.nDot(h));

            const schlick = fresnel.Schlick1.init(self.f0);

            var fr: Vec4f = undefined;
            const gg = ggx.Iso.reflectionF(n_dot_wi, n_dot_wo, wo_dot_h, n_dot_h, alpha, schlick, &fr);
            const comp = ggx.ilmEpDielectric(n_dot_wo, alpha, self.ior);

            return bxdf.Result.init(@splat(4, n_dot_wi * comp) * gg.reflection, fr[0] * gg.pdf());
        }
    }

    pub fn sample(self: Sample, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        const ior = self.ior;

        if (self.super.alpha[0] > 0.0) {
            return self.roughSample(ior, sampler, rng);
        } else if (self.thickness > 0.0) {
            return self.thinSample(ior, sampler, rng);
        } else {
            return self.thickSample(ior, sampler, rng);
        }
    }

    fn thickSample(self: Sample, ior: f32, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        var eta_i = self.ior_outside;
        var eta_t = ior;

        const wo = self.super.wo;

        if (eta_i == eta_t) {
            return .{
                .reflection = self.super.albedo,
                .wi = -wo,
                .pdf = 1.0,
                .typef = bxdf.TypeFlag.init1(.SpecularTransmission),
            };
        }

        var n = self.super.layer.n;

        if (!self.super.sameHemisphere(wo)) {
            n = -n;
            std.mem.swap(f32, &eta_i, &eta_t);
        }

        const n_dot_wo = std.math.min(@fabs(math.dot3(n, wo)), 1.0);
        const eta = eta_i / eta_t;
        const sint2 = (eta * eta) * (1.0 - n_dot_wo * n_dot_wo);

        var n_dot_t: f32 = undefined;
        var f: f32 = undefined;
        if (sint2 >= 1.0) {
            n_dot_t = 0.0;
            f = 1.0;
        } else {
            n_dot_t = @sqrt(1.0 - sint2);
            f = fresnel.dielectric(n_dot_wo, n_dot_t, eta_i, eta_t);
        }

        const p = sampler.sample1D(rng, 0);
        if (p <= f) {
            return reflect(wo, n, n_dot_wo);
        } else {
            return thickRefract(wo, n, n_dot_wo, n_dot_t, eta);
        }
    }

    fn thinSample(self: Sample, ior: f32, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        // Thin material is always double sided, so no need to check hemisphere.
        const eta_i = self.ior_outside;
        const eta_t = ior;

        const wo = self.super.wo;
        const n = self.super.layer.n;

        const n_dot_wo = std.math.min(@fabs(math.dot3(n, wo)), 1.0);
        const eta = eta_i / eta_t;
        const sint2 = (eta * eta) * (1.0 - n_dot_wo * n_dot_wo);

        var f: f32 = undefined;
        if (sint2 >= 1.0) {
            f = 1.0;
        } else {
            const n_dot_t = @sqrt(1.0 - sint2);
            f = fresnel.dielectric(n_dot_wo, n_dot_t, eta_i, eta_t);
        }

        const p = sampler.sample1D(rng, 0);
        if (p <= f) {
            return reflect(wo, n, n_dot_wo);
        } else {
            const n_dot_wi = hlp.clamp(n_dot_wo);
            const approx_dist = self.thickness / n_dot_wi;

            const attenuation = inthlp.attenuation3(self.absorption_coef, approx_dist);

            return thinRefract(wo, attenuation);
        }
    }

    fn roughSample(self: Sample, ior_t: f32, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        const quo_ior = IoR{ .eta_i = self.ior_outside, .eta_t = ior_t };

        const wo = self.super.wo;

        if (quo_ior.eta_i == quo_ior.eta_t) {
            return .{
                .reflection = self.super.albedo,
                .wi = -wo,
                .pdf = 1.0,
                .typef = bxdf.TypeFlag.init1(.SpecularTransmission),
            };
        }

        const alpha = self.super.alpha;

        const same_side = self.super.sameHemisphere(wo);

        const layer = self.super.layer.swapped(same_side);
        const ior = quo_ior.swapped(same_side);

        const xi = sampler.sample2D(rng, 0);

        var n_dot_h: f32 = undefined;
        const h = ggx.Aniso.sample(wo, alpha, xi, layer, &n_dot_h);

        const n_dot_wo = layer.clampAbsNdot(wo);
        const wo_dot_h = hlp.clampDot(wo, h);

        const eta = ior.eta_i / ior.eta_t;
        const sint2 = (eta * eta) * (1.0 - wo_dot_h * wo_dot_h);

        var wi_dot_h: f32 = undefined;
        var f: f32 = undefined;
        if (sint2 >= 1.0) {
            wi_dot_h = 0.0;
            f = 1.0;
        } else {
            wi_dot_h = @sqrt(1.0 - sint2);
            const cos_x = if (ior.eta_i > ior.eta_t) wi_dot_h else wo_dot_h;
            f = fresnel.schlick1(cos_x, self.f0);
        }

        var result = bxdf.Sample{};

        const p = sampler.sample1D(rng, 0);
        if (p <= f) {
            const n_dot_wi = ggx.Iso.reflectNoFresnel(
                wo,
                h,
                n_dot_wo,
                n_dot_h,
                wi_dot_h,
                wo_dot_h,
                alpha[0],
                layer,
                &result,
            );

            result.reflection *= @splat(4, f * n_dot_wi);
            result.pdf *= f;
        } else {
            const r_wo_dot_h = if (same_side) -wo_dot_h else wo_dot_h;
            const n_dot_wi = ggx.Iso.refractNoFresnel(
                wo,
                h,
                n_dot_wo,
                n_dot_h,
                -wi_dot_h,
                r_wo_dot_h,
                alpha[0],
                ior,
                layer,
                &result,
            );

            const omf = 1.0 - f;

            result.reflection *= @splat(4, omf * n_dot_wi) * self.super.albedo;
            result.pdf *= omf;
        }

        result.reflection *= @splat(4, ggx.ilmEpDielectric(n_dot_wo, alpha[0], ior_t));

        return result;
    }

    fn reflect(wo: Vec4f, n: Vec4f, n_dot_wo: f32) bxdf.Sample {
        return .{
            .reflection = @splat(4, @as(f32, 1.0)),
            .wi = math.normalize3(@splat(4, 2.0 * n_dot_wo) * n - wo),
            .pdf = 1.0,
            .typef = bxdf.TypeFlag.init1(.SpecularReflection),
        };
    }

    fn thickRefract(wo: Vec4f, n: Vec4f, n_dot_wo: f32, n_dot_t: f32, eta: f32) bxdf.Sample {
        return .{
            .reflection = @splat(4, @as(f32, 1.0)),
            .wi = math.normalize3(@splat(4, eta * n_dot_wo - n_dot_t) * n - @splat(4, eta) * wo),
            .pdf = 1.0,
            .typef = bxdf.TypeFlag.init1(.SpecularTransmission),
        };
    }

    fn thinRefract(wo: Vec4f, color: Vec4f) bxdf.Sample {
        return .{
            .reflection = color,
            .wi = -wo,
            .pdf = 1.0,
            .typef = bxdf.TypeFlag.init1(.Straight),
        };
    }
};
