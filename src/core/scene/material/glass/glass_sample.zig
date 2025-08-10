const smpl = @import("../sample_base.zig");
const Base = smpl.Base;
const IoR = smpl.IoR;
const Material = @import("../material_base.zig").Base;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const ccoef = @import("../collision_coefficients.zig");
const fresnel = @import("../fresnel.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const ggx = @import("../ggx.zig");

const base = @import("base");
const math = base.math;
const Frame = math.Frame;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Sample = struct {
    super: Base,

    absorption_coef: Vec4f,
    ior: f32,
    ior_outside: f32,
    f0: f32,
    specular: f32,
    abbe: f32,
    wavelength: f32,
    thickness: f32,

    pub fn init(
        rs: Renderstate,
        wo: Vec4f,
        absorption_coef: Vec4f,
        ior: f32,
        alpha: f32,
        specular: f32,
        thickness: f32,
        abbe: f32,
        priority: i8,
    ) Sample {
        const reg_alpha = rs.regularizeAlpha(@splat(alpha));
        const rough = reg_alpha[0] > 0.0;
        const ior_outside = rs.ior;

        var super = Base.init(rs, wo, @splat(1.0), reg_alpha, priority);

        super.properties.can_evaluate = rough and ior != ior_outside;
        super.properties.translucent = thickness > 0.0;

        return .{
            .super = super,
            .absorption_coef = absorption_coef,
            .ior = ior,
            .ior_outside = ior_outside,
            .f0 = if (rough) fresnel.Schlick.IorToF0(ior, ior_outside) else 0.0,
            .specular = specular,
            .abbe = abbe,
            .wavelength = rs.wavelength,
            .thickness = thickness,
        };
    }

    pub fn evaluate(self: *const Sample, wi: Vec4f, max_splits: u32) bxdf.Result {
        const alpha = self.super.alpha[0];
        const rough = alpha > 0.0;

        if (self.ior == self.ior_outside or !rough or self.super.properties.lower_priority or
            (self.super.avoidCaustics() and alpha <= ggx.MinAlpha))
        {
            return bxdf.Result.empty();
        }

        const frame = self.super.frame;

        const split = max_splits > 1;

        const s = self.specular;

        const wo = self.super.wo;
        if (!self.super.sameHemisphere(wo)) {
            // The way our thin materials work, wo will always be on "sameHemisphere" of the sample
            // So we know we have to deal with thick refraction in this case

            const ior = IoR{ .eta_i = self.ior, .eta_t = self.ior_outside };

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

            const gg = ggx.Iso.refractionF(
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

            const split_pdf = if (split) 1.0 else gg.f[0];

            return bxdf.Result.init(
                @as(Vec4f, @splat(math.min(n_dot_wi, n_dot_wo) * comp * s)) * self.super.albedo * gg.r.reflection,
                split_pdf * gg.r.pdf,
            );
        } else if (self.super.sameHemisphere(wi)) {
            // Only evaluate "front" with light from the same side
            // Shadow rays connect directly through "thin" glass and the MIS is a bit sketchy in this case anyway

            const n_dot_wi = frame.clampNdot(wi);
            const n_dot_wo = frame.clampAbsNdot(wo);

            const h = math.normalize3(wo + wi);

            const wo_dot_h = math.safe.clampDot(wo, h);

            const schlick = fresnel.Schlick.init(@splat(self.f0));

            const gg = ggx.Iso.reflectionF(h, frame.z, n_dot_wi, n_dot_wo, wo_dot_h, alpha, schlick);
            const comp = ggx.ilmEpDielectric(n_dot_wo, alpha, self.f0);

            const split_pdf = if (split) 1.0 else gg.f[0];
            return bxdf.Result.init(@as(Vec4f, @splat(n_dot_wi * comp * s)) * gg.r.reflection, split_pdf * gg.r.pdf);
        }

        return bxdf.Result.empty();
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

    pub fn sample(self: *const Sample, sampler: *Sampler, max_splits: u32, buffer: *bxdf.Samples) []bxdf.Sample {
        const split = max_splits > 1;

        if (self.thickness > 0.0) {
            if (self.super.alpha[0] > 0.0) {
                return self.roughSample(true, @splat(1.0), self.ior, 0.0, sampler, split, buffer);
            } else {
                return self.specularSample(true, @splat(1.0), self.ior, 0.0, sampler, split, buffer);
            }
        } else {
            if (0.0 == self.abbe) {
                if (self.super.alpha[0] > 0.0) {
                    return self.roughSample(false, @splat(1.0), self.ior, 0.0, sampler, split, buffer);
                } else {
                    return self.specularSample(false, @splat(1.0), self.ior, 0.0, sampler, split, buffer);
                }
            } else {
                var wavelength = self.wavelength;
                var ior = self.ior;

                const r1 = sampler.sample1D();
                const weight = wavelengthSpectrumWeight(&wavelength, r1);

                const sqr_wl = wavelength * wavelength;
                ior = ior + ((ior - 1.0) / self.abbe) * (523655.0 / sqr_wl - 1.5168);

                if (self.super.alpha[0] > 0.0) {
                    return self.roughSample(false, weight, ior, wavelength, sampler, split, buffer);
                } else {
                    return self.specularSample(false, weight, ior, wavelength, sampler, split, buffer);
                }
            }
        }
    }

    fn specularSample(
        self: *const Sample,
        comptime Thin: bool,
        weight: Vec4f,
        ior: f32,
        wavelength: f32,
        sampler: *Sampler,
        split: bool,
        buffer: *bxdf.Samples,
    ) []bxdf.Sample {
        var eta_i = self.ior_outside;
        var eta_t = ior;

        const wo = self.super.wo;

        if (eta_i == eta_t or self.super.properties.lower_priority) {
            buffer[0] = .{
                .reflection = weight,
                .wi = -wo,
                .pdf = 1.0,
                .split_weight = 1.0,
                .wavelength = wavelength,
                .path = .singularTransmission,
            };

            return buffer[0..1];
        }

        var n = self.super.frame.z;

        if (!Thin) {
            // Thin material is always double sided, so no need to check hemisphere.
            if (!self.super.sameHemisphere(wo)) {
                n = -n;
                std.mem.swap(f32, &eta_i, &eta_t);
            }
        }

        const n_dot_wo = math.min(@abs(math.dot3(n, wo)), 1.0);
        const eta = eta_i / eta_t;
        const sint2 = (eta * eta) * (1.0 - n_dot_wo * n_dot_wo);

        const s = self.specular;

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
            buffer[0] = reflect(weight, wo, n, n_dot_wo, wavelength, f, s);

            if (1.0 == f) {
                return buffer[0..1];
            }

            if (Thin) {
                buffer[1] = self.thinSpecularRefract(wo, n_dot_wo, 1.0 - f);
            } else {
                buffer[1] = thickSpecularRefract(weight, wo, n, n_dot_wo, n_dot_t, eta, wavelength, 1.0 - f);
            }

            return buffer[0..2];
        } else {
            const p = sampler.sample1D();
            if (p <= f) {
                buffer[0] = reflect(weight, wo, n, n_dot_wo, wavelength, 1.0, s);
            } else {
                if (Thin) {
                    buffer[0] = self.thinSpecularRefract(wo, n_dot_wo, 1.0);
                } else {
                    buffer[0] = thickSpecularRefract(weight, wo, n, n_dot_wo, n_dot_t, eta, wavelength, 1.0);
                }
            }

            return buffer[0..1];
        }
    }

    fn roughSample(
        self: *const Sample,
        comptime Thin: bool,
        weight: Vec4f,
        ior_t: f32,
        wavelength: f32,
        sampler: *Sampler,
        split: bool,
        buffer: *bxdf.Samples,
    ) []bxdf.Sample {
        const quo_ior = IoR{ .eta_i = self.ior_outside, .eta_t = ior_t };

        const wo = self.super.wo;

        if (math.eq(quo_ior.eta_i, quo_ior.eta_t, 2.e-7) or self.super.properties.lower_priority) {
            buffer[0] = .{
                .reflection = weight,
                .wi = -wo,
                .pdf = 1.0,
                .split_weight = 1.0,
                .wavelength = wavelength,
                .path = .singularTransmission,
            };
            return buffer[0..1];
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
        const wo_dot_h = math.safe.clampDot(wo, h);

        const eta = ior.eta_i / ior.eta_t;
        const sint2 = (eta * eta) * (1.0 - wo_dot_h * wo_dot_h);

        const s = self.specular;

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

        if (split) {
            const ep = ggx.ilmEpDielectric(n_dot_wo, alpha[0], self.f0);

            {
                const n_dot_wi = ggx.Iso.reflectNoFresnel(wo, h, n_dot_wo, n_dot_h, wo_dot_h, alpha[0], frame, &buffer[0]);

                buffer[0].reflection *= @as(Vec4f, @splat(n_dot_wi * ep * s)) * weight;
                buffer[0].split_weight = f;
                buffer[0].wavelength = wavelength;
            }

            if (1.0 == f) {
                return buffer[0..1];
            }

            {
                const n_dot_wi = self.roughRefract(
                    Thin,
                    same_side,
                    frame,
                    wo,
                    h,
                    n_dot_wo,
                    n_dot_h,
                    wi_dot_h,
                    wo_dot_h,
                    alpha[0],
                    ior,
                    &buffer[1],
                );

                if (n_dot_wi < 0.0) {
                    return buffer[0..1];
                }

                buffer[1].reflection *= @as(Vec4f, @splat(n_dot_wi * ep)) * weight * self.super.albedo;
                buffer[1].split_weight = 1.0 - f;
                buffer[1].wavelength = wavelength;
            }

            return buffer[0..2];
        } else {
            var result = &buffer[0];

            const ep = ggx.ilmEpDielectric(n_dot_wo, alpha[0], self.f0);

            const p = s3[0];
            if (p <= f) {
                const n_dot_wi = ggx.Iso.reflectNoFresnel(wo, h, n_dot_wo, n_dot_h, wo_dot_h, alpha[0], frame, result);

                result.reflection *= @as(Vec4f, @splat(f * n_dot_wi * ep * s)) * weight;
                result.pdf *= f;
            } else {
                const n_dot_wi = self.roughRefract(
                    Thin,
                    same_side,
                    frame,
                    wo,
                    h,
                    n_dot_wo,
                    n_dot_h,
                    wi_dot_h,
                    wo_dot_h,
                    alpha[0],
                    ior,
                    result,
                );

                if (n_dot_wi < 0.0) {
                    return buffer[0..0];
                }

                const omf = 1.0 - f;

                result.reflection *= @as(Vec4f, @splat(omf * n_dot_wi * ep)) * weight * self.super.albedo;
                result.pdf *= omf;
            }

            result.split_weight = 1.0;
            result.wavelength = wavelength;

            return buffer[0..1];
        }
    }

    fn reflect(weight: Vec4f, wo: Vec4f, n: Vec4f, n_dot_wo: f32, wavelength: f32, split_weight: f32, specular: f32) bxdf.Sample {
        return .{
            .reflection = @as(Vec4f, @splat(specular)) * weight,
            .wi = math.normalize3(@as(Vec4f, @splat(2.0 * n_dot_wo)) * n - wo),
            .pdf = 1.0,
            .split_weight = split_weight,
            .wavelength = wavelength,
            .path = .singularReflection,
        };
    }

    fn roughRefract(
        self: *const Sample,
        comptime Thin: bool,
        same_side: bool,
        frame: Frame,
        wo: Vec4f,
        h: Vec4f,
        n_dot_wo: f32,
        n_dot_h: f32,
        wi_dot_h: f32,
        wo_dot_h: f32,
        alpha: f32,
        ior: IoR,
        result: *bxdf.Sample,
    ) f32 {
        if (Thin) {
            const thin_frame = Frame.init(-wo);
            const tangent_h = frame.worldToFrame(h);
            const thin_h = thin_frame.frameToWorld(tangent_h);

            const thin_n_dot_wo = tangent_h[2];
            const thin_n_dot_h = math.saturate(tangent_h[2]);
            const thin_wo_dot_h = 1.0;

            const n_dot_wi = ggx.Iso.reflectNoFresnel(
                thin_h,
                thin_h,
                thin_n_dot_wo,
                thin_n_dot_h,
                thin_wo_dot_h,
                alpha,
                thin_frame,
                result,
            );

            if (self.super.sameHemisphere(result.wi)) {
                return -1.0;
            }

            const approx_dist = self.thickness / n_dot_wo;
            const attenuation = ccoef.attenuation3(self.absorption_coef, approx_dist);

            result.reflection *= attenuation;
            result.path = .straight;

            return n_dot_wi;
        } else {
            const r_wo_dot_h = if (same_side) -wo_dot_h else wo_dot_h;
            return ggx.Iso.refractNoFresnel(
                wo,
                h,
                n_dot_wo,
                n_dot_h,
                -wi_dot_h,
                r_wo_dot_h,
                alpha,
                ior,
                frame,
                result,
            );
        }
    }

    fn thinSpecularRefract(self: *const Sample, wo: Vec4f, n_dot_wo: f32, split_weight: f32) bxdf.Sample {
        const approx_dist = self.thickness / math.safe.clamp(n_dot_wo);
        const attenuation = ccoef.attenuation3(self.absorption_coef, approx_dist);

        return .{
            .reflection = attenuation,
            .wi = -wo,
            .pdf = 1.0,
            .split_weight = split_weight,
            .wavelength = 0.0,
            .path = .straight,
        };
    }

    fn thickSpecularRefract(
        weight: Vec4f,
        wo: Vec4f,
        n: Vec4f,
        n_dot_wo: f32,
        n_dot_t: f32,
        eta: f32,
        wavelength: f32,
        split_weight: f32,
    ) bxdf.Sample {
        return .{
            .reflection = weight,
            .wi = math.normalize3(@as(Vec4f, @splat(eta * n_dot_wo - n_dot_t)) * n - @as(Vec4f, @splat(eta)) * wo),
            .pdf = 1.0,
            .split_weight = split_weight,
            .wavelength = wavelength,
            .path = .singularTransmission,
        };
    }
};
