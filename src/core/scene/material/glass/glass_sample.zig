const sample = @import("../sample_base.zig");
const Base = sample.Base;
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
        const reg_alpha = rs.regularizeAlpha(@splat(alpha));

        var super = Base.init(
            rs,
            wo,
            @splat(1.0),
            reg_alpha,
            thickness,
        );

        const rough = reg_alpha[0] > 0.0;

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

            const h = -math.normalize3(@as(Vec4f, @splat(ior.eta_t)) * wi + @as(Vec4f, @splat(ior.eta_i)) * wo);

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

            const schlick = fresnel.Schlick.init(@splat(self.f0));

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
                @as(Vec4f, @splat(math.min(n_dot_wi, n_dot_wo) * comp)) * self.super.albedo * gg.reflection,
                gg.pdf(),
            );
        } else {
            const n_dot_wi = frame.clampNdot(wi);
            const n_dot_wo = frame.clampAbsNdot(wo);

            const h = math.normalize3(wo + wi);

            const wo_dot_h = hlp.clampDot(wo, h);

            const schlick = fresnel.Schlick.init(@splat(self.f0));

            const gg = ggx.Iso.reflectionF(h, frame.n, n_dot_wi, n_dot_wo, wo_dot_h, alpha, schlick);
            const comp = ggx.ilmEpDielectric(n_dot_wo, alpha, self.f0);

            return bxdf.Result.init(@as(Vec4f, @splat(n_dot_wi * comp)) * gg.r.reflection, gg.f[0] * gg.r.pdf());
        }
    }

    fn wavelengthSpectrumWeight(wavelength: *f32, r: f32) Vec4f {
        if (0.0 == wavelength.*) {
            const start = Material.Start_wavelength;
            const end = Material.End_wavelength;

            wavelength.* = start + (end - start) * r;

            return Material.spectrumAtWavelength(wavelength.*, 1.0) * @as(Vec4f, @splat(3.0));
        }

        return @splat(1.0);
    }

    pub fn sample(self: *const Sample, sampler: *Sampler, split: bool, buffer: *bxdf.Samples) []bxdf.Sample {
        var ior = self.ior;

        if (self.super.alpha[0] > 0.0) {
            if (0.0 == self.abbe) {
                var result = self.roughSample(ior, sampler);
                result.wavelength = 0.0;
                buffer[0] = result;
                return buffer[0..1];
            } else {
                var wavelength = self.wavelength;

                const r = sampler.sample1D();
                const weight = wavelengthSpectrumWeight(&wavelength, r);

                const sqr_wl = wavelength * wavelength;
                ior = ior + ((ior - 1.0) / self.abbe) * (523655.0 / sqr_wl - 1.5168);

                var result = self.roughSample(ior, sampler);
                result.reflection *= weight;
                result.wavelength = wavelength;
                buffer[0] = result;
                return buffer[0..1];
            }
        } else if (self.super.thickness > 0.0) {
            return self.thinSample(ior, sampler, split, buffer);
        } else {
            if (0.0 == self.abbe) {
                const p = sampler.sample1D();

                var result = self.thickSample(ior, p, split, buffer);

                for (result) |*r| {
                    r.wavelength = 0.0;
                }

                return result;
            } else {
                var wavelength = self.wavelength;

                const r = sampler.sample2D();
                const weight = wavelengthSpectrumWeight(&wavelength, r[1]);

                const sqr_wl = wavelength * wavelength;
                ior = ior + ((ior - 1.0) / self.abbe) * (523655.0 / sqr_wl - 1.5168);

                var result = self.thickSample(ior, r[0], false, buffer);
                result[0].reflection *= weight;
                result[0].wavelength = wavelength;
                return result;
            }
        }
    }

    fn thickSample(self: *const Sample, ior: f32, p: f32, split: bool, buffer: *bxdf.Samples) []bxdf.Sample {
        var eta_i = self.ior_outside;
        var eta_t = ior;

        const wo = self.super.wo;

        if (eta_i == eta_t) {
            buffer[0] = .{
                .reflection = @splat(1.0),
                .wi = -wo,
                .pdf = 1.0,
                .class = .{ .specular = true, .transmission = true },
            };

            return buffer[0..1];
        }

        var n = self.super.frame.n;

        if (!self.super.sameHemisphere(wo)) {
            n = -n;
            std.mem.swap(f32, &eta_i, &eta_t);
        }

        const n_dot_wo = math.min(@fabs(math.dot3(n, wo)), 1.0);
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

        if (split) {
            buffer[0] = reflect(wo, n, n_dot_wo, f, 0.5);
            buffer[1] = thickRefract(wo, n, n_dot_wo, n_dot_t, eta, 1.0 - f, 0.5);

            return buffer[0..2];
        } else {
            if (p <= f) {
                buffer[0] = reflect(wo, n, n_dot_wo, 1.0, 1.0);
            } else {
                buffer[0] = thickRefract(wo, n, n_dot_wo, n_dot_t, eta, 1.0, 1.0);
            }

            return buffer[0..1];
        }
    }

    fn thinSample(self: *const Sample, ior: f32, sampler: *Sampler, split: bool, buffer: *bxdf.Samples) []bxdf.Sample {
        // Thin material is always double sided, so no need to check hemisphere.
        const eta_i = self.ior_outside;
        const eta_t = ior;

        const wo = self.super.wo;
        const n = self.super.frame.n;

        const n_dot_wo = math.min(@fabs(math.dot3(n, wo)), 1.0);
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
            buffer[0] = reflect(wo, n, n_dot_wo, f, 0.5 / f);
            buffer[0].wavelength = 0.0;

            const n_dot_wi = hlp.clamp(n_dot_wo);
            const approx_dist = self.super.thickness / n_dot_wi;

            const attenuation = inthlp.attenuation3(self.absorption_coef, approx_dist);

            buffer[1] = thinRefract(wo, attenuation, 1.0 - f, 0.5 / (1.0 - f));

            return buffer[0..2];
        } else {
            const p = sampler.sample1D();
            if (p <= f) {
                buffer[0] = reflect(wo, n, n_dot_wo, 1.0, 1.0);
                buffer[0].wavelength = 0.0;
            } else {
                const n_dot_wi = hlp.clamp(n_dot_wo);
                const approx_dist = self.super.thickness / n_dot_wi;

                const attenuation = inthlp.attenuation3(self.absorption_coef, approx_dist);

                buffer[0] = thinRefract(wo, attenuation, 1.0, 1.0);
            }

            return buffer[0..1];
        }
    }

    fn roughSample(self: *const Sample, ior_t: f32, sampler: *Sampler) bxdf.Sample {
        const quo_ior = IoR{ .eta_i = self.ior_outside, .eta_t = ior_t };

        const wo = self.super.wo;

        if (math.eq(quo_ior.eta_i, quo_ior.eta_t, 2.e-7)) {
            return .{
                .reflection = @splat(1.0),
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

            result.reflection *= @splat(f * n_dot_wi);
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

            result.reflection *= @as(Vec4f, @splat(omf * n_dot_wi)) * self.super.albedo;
            result.pdf *= omf;
        }

        result.reflection *= @splat(ggx.ilmEpDielectric(n_dot_wo, alpha[0], self.f0));

        return result;
    }

    fn reflect(wo: Vec4f, n: Vec4f, n_dot_wo: f32, f: f32, pdf: f32) bxdf.Sample {
        return .{
            .reflection = @splat(f),
            .wi = math.normalize3(@as(Vec4f, @splat(2.0 * n_dot_wo)) * n - wo),
            .pdf = pdf,
            .class = .{ .specular = true, .reflection = true },
        };
    }

    fn thickRefract(wo: Vec4f, n: Vec4f, n_dot_wo: f32, n_dot_t: f32, eta: f32, omf: f32, pdf: f32) bxdf.Sample {
        return .{
            .reflection = @as(Vec4f, @splat(omf)),
            .wi = math.normalize3(@as(Vec4f, @splat(eta * n_dot_wo - n_dot_t)) * n - @as(Vec4f, @splat(eta)) * wo),
            .pdf = pdf,
            .class = .{ .specular = true, .transmission = true },
        };
    }

    fn thinRefract(wo: Vec4f, color: Vec4f, omf: f32, pdf: f32) bxdf.Sample {
        return .{
            .reflection = @as(Vec4f, @splat(omf)) * color,
            .wi = -wo,
            .pdf = pdf,
            .wavelength = 0.0,
            .class = .{ .straight = true },
        };
    }
};
