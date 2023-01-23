const sample = @import("../sample_base.zig");
const Base = sample.SampleBase;
const IoR = sample.IoR;
const Material = @import("../material_base.zig").Base;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const fresnel = @import("../fresnel.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const hlp = @import("../sample_helper.zig");
const inthlp = @import("../../../rendering/integrator/helper.zig");
const ggx = @import("../ggx.zig");

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Sample = struct {
    super: Base,

    absorption_coef: Vec4f,
    ior: f32,
    ior_outside: f32,
    f0: f32,
    abbe: f32,
    wavelength: f32,

    pub fn init(
        rs: Renderstate,
        wo: Vec4f,
        absorption_coef: Vec4f,
        ior: f32,
        ior_outside: f32,
        alpha: f32,
        thickness: f32,
        abbe: f32,
        wavelength: f32,
    ) Sample {
        var super = Base.init(
            rs,
            wo,
            @splat(4, @as(f32, 1.0)),
            @splat(2, alpha),
            thickness,
        );

        const rough = alpha > 0.0;

        super.properties.can_evaluate = rough and ior != ior_outside;
        super.properties.translucent = thickness > 0.0;

        return .{
            .super = super,
            .absorption_coef = absorption_coef,
            .ior = ior,
            .ior_outside = ior_outside,
            .f0 = if (rough) fresnel.Schlick.IorToF0(ior, ior_outside) else 0.0,
            .abbe = abbe,
            .wavelength = wavelength,
        };
    }

    pub fn evaluate(self: *const Sample, wi: Vec4f) bxdf.Result {
        const alpha = self.super.alpha[0];
        const rough = alpha > 0.0;

        if (self.ior == self.ior_outside or !rough or
            (self.super.avoidCaustics() and alpha <= ggx.Min_alpha))
        {
            return bxdf.Result.empty();
        }

        const frame = self.super.frame;

        const wo = self.super.wo;
        if (!self.super.sameHemisphere(wo)) {
            const quo_ior = IoR{ .eta_i = self.ior_outside, .eta_t = self.ior };
            const ior = quo_ior.swapped(false);

            const h = -math.normalize3(@splat(4, ior.eta_t) * wi + @splat(4, ior.eta_i) * wo);

            const wi_dot_h = math.dot3(wi, h);
            if (wi_dot_h <= 0.0) {
                return bxdf.Result.empty();
            }

            const wo_dot_h = math.dot3(wo, h);
            const eta = ior.eta_i / ior.eta_t;
            const sint2 = (eta * eta) * (1.0 - wo_dot_h * wo_dot_h);

            if (sint2 >= 1.0) {
                return bxdf.Result.empty();
            }

            const n_dot_wi = frame.clampNdot(wi);
            const n_dot_wo = frame.clampAbsNdot(wo);
            const n_dot_h = math.saturate(self.super.frame.nDot(h));

            const schlick = fresnel.Schlick.init(@splat(4, self.f0));

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

            const comp = ggx.ilmEpDielectric(n_dot_wo, alpha, self.f0);

            return bxdf.Result.init(
                @splat(4, std.math.min(n_dot_wi, n_dot_wo) * comp) * self.super.albedo * gg.reflection,
                gg.pdf(),
            );
        } else {
            const n_dot_wi = frame.clampNdot(wi);
            const n_dot_wo = frame.clampAbsNdot(wo);

            const h = math.normalize3(wo + wi);

            const wo_dot_h = hlp.clampDot(wo, h);

            const schlick = fresnel.Schlick.init(@splat(4, self.f0));

            const gg = ggx.Iso.reflectionF(h, frame.n, n_dot_wi, n_dot_wo, wo_dot_h, alpha, schlick);
            const comp = ggx.ilmEpDielectric(n_dot_wo, alpha, self.f0);

            return bxdf.Result.init(@splat(4, n_dot_wi * comp) * gg.r.reflection, gg.f[0] * gg.r.pdf());
        }
    }

    pub fn sample(self: *const Sample, sampler: *Sampler, split: bool, buffer: *Base.BxdfSamples) []bxdf.Sample {
        var ior = self.ior;

        if (self.super.alpha[0] > 0.0) {
            var result = self.roughSample(ior, sampler);
            result.wavelength = 0.0;
            buffer[0] = result;
            return buffer[0..1];
        } else if (self.super.thickness > 0.0) {
            return self.thinSample(ior, sampler, split, buffer);
        } else {
            if (0.0 == self.abbe) {
                const p = sampler.sample1D();
                var result = self.thickSample(ior, p);
                result.wavelength = 0.0;
                buffer[0] = result;
                return buffer[0..1];
            } else {
                var weight: Vec4f = undefined;
                var wavelength = self.wavelength;

                const r = sampler.sample2D();

                if (0.0 == wavelength) {
                    const start = Material.Start_wavelength;
                    const end = Material.End_wavelength;

                    wavelength = start + (end - start) * r[1];

                    weight = Material.spectrumAtWavelength(wavelength, 1.0);
                    weight *= @splat(4, @as(f32, 3.0));
                } else {
                    weight = @splat(4, @as(f32, 1.0));
                }

                const sqr_wl = wavelength * wavelength;
                ior = ior + ((ior - 1.0) / self.abbe) * (523655.0 / sqr_wl - 1.5168);

                var result = self.thickSample(ior, r[0]);
                result.reflection *= weight;
                result.wavelength = wavelength;
                buffer[0] = result;
                return buffer[0..1];
            }
        }
    }

    fn thickSample(self: *const Sample, ior: f32, p: f32) bxdf.Sample {
        var eta_i = self.ior_outside;
        var eta_t = ior;

        const wo = self.super.wo;

        if (eta_i == eta_t) {
            return .{
                .reflection = @splat(4, @as(f32, 1.0)),
                .wi = -wo,
                .pdf = 1.0,
                .class = .{ .specular = true, .transmission = true },
            };
        }

        var n = self.super.frame.n;

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

        if (p <= f) {
            var result = reflect(wo, n, n_dot_wo, f);
            result.pdf *= f;
            return result;
        } else {
            return thickRefract(wo, n, n_dot_wo, n_dot_t, eta);
        }
    }

    fn thinSample(self: *const Sample, ior: f32, sampler: *Sampler, split: bool, buffer: *Base.BxdfSamples) []bxdf.Sample {
        // Thin material is always double sided, so no need to check hemisphere.
        const eta_i = self.ior_outside;
        const eta_t = ior;

        const wo = self.super.wo;
        const n = self.super.frame.n;

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

        if (split) {
            buffer[0] = reflect(wo, n, n_dot_wo, f);
            buffer[0].wavelength = 0.0;

            const n_dot_wi = hlp.clamp(n_dot_wo);
            const approx_dist = self.super.thickness / n_dot_wi;
            const attenuation = inthlp.attenuation3(self.absorption_coef, approx_dist);
            const omf = 1.0 - f;
            buffer[1] = thinRefract(wo, attenuation, omf);

            return buffer[0..2];
        } else {
            const p = sampler.sample1D();
            if (p <= f) {
                buffer[0] = reflect(wo, n, n_dot_wo, f);
                buffer[0].pdf *= f;
                buffer[0].wavelength = 0.0;
            } else {
                const n_dot_wi = hlp.clamp(n_dot_wo);
                const approx_dist = self.super.thickness / n_dot_wi;
                const attenuation = inthlp.attenuation3(self.absorption_coef, approx_dist);
                const omf = 1.0 - f;
                buffer[0] = thinRefract(wo, attenuation, omf);
                buffer[0].pdf *= omf;
            }

            return buffer[0..1];
        }
    }

    fn roughSample(self: *const Sample, ior_t: f32, sampler: *Sampler) bxdf.Sample {
        const quo_ior = IoR{ .eta_i = self.ior_outside, .eta_t = ior_t };

        const wo = self.super.wo;

        if (quo_ior.eta_i == quo_ior.eta_t) {
            return .{
                .reflection = @splat(4, @as(f32, 1.0)),
                .wi = -wo,
                .pdf = 1.0,
                .class = .{ .specular = true, .transmission = true },
            };
        }

        const alpha = self.super.alpha;

        const same_side = self.super.sameHemisphere(wo);

        const frame = self.super.frame.swapped(same_side);
        const ior = quo_ior.swapped(same_side);

        const s3 = sampler.sample3D();
        const xi = Vec2f{ s3[1], s3[2] };

        var n_dot_h: f32 = undefined;
        const h = ggx.Aniso.sample(wo, alpha, xi, frame, &n_dot_h);

        const n_dot_wo = frame.clampAbsNdot(wo);
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

        const p = s3[0];
        if (p <= f) {
            const n_dot_wi = ggx.Iso.reflectNoFresnel(
                wo,
                h,
                n_dot_wo,
                n_dot_h,
                wi_dot_h,
                wo_dot_h,
                alpha[0],
                frame,
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
                frame,
                &result,
            );

            const omf = 1.0 - f;

            result.reflection *= @splat(4, omf * n_dot_wi) * self.super.albedo;
            result.pdf *= omf;
        }

        result.reflection *= @splat(4, ggx.ilmEpDielectric(n_dot_wo, alpha[0], self.f0));

        return result;
    }

    fn reflect(wo: Vec4f, n: Vec4f, n_dot_wo: f32, f: f32) bxdf.Sample {
        return .{
            .reflection = @splat(4, f),
            .wi = math.normalize3(@splat(4, 2.0 * n_dot_wo) * n - wo),
            .pdf = 1.0,
            .class = .{ .specular = true, .reflection = true },
        };
    }

    fn thickRefract(wo: Vec4f, n: Vec4f, n_dot_wo: f32, n_dot_t: f32, eta: f32) bxdf.Sample {
        return .{
            .reflection = @splat(4, @as(f32, 1.0)),
            .wi = math.normalize3(@splat(4, eta * n_dot_wo - n_dot_t) * n - @splat(4, eta) * wo),
            .pdf = 1.0,
            .class = .{ .specular = true, .transmission = true },
        };
    }

    fn thinRefract(wo: Vec4f, color: Vec4f, omf: f32) bxdf.Sample {
        return .{
            .reflection = @splat(4, omf) * color,
            .wi = -wo,
            .pdf = 1.0,
            .class = .{ .straight = true },
            .wavelength = 0.0,
        };
    }
};
