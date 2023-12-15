const sample = @import("../sample_base.zig");
const Base = sample.Base;
const IoR = sample.IoR;
const Coating = @import("substitute_coating.zig").Coating;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const ccoef = @import("../collision_coefficients.zig");
const diffuse = @import("../diffuse.zig");
const fresnel = @import("../fresnel.zig");
const inthlp = @import("../../../rendering/integrator/helper.zig");
const ggx = @import("../ggx.zig");

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Sample = struct {
    super: Base,

    coating: Coating = .{},

    f0: Vec4f,
    absorption_coef: Vec4f = undefined,

    ior: IoR,

    metallic: f32,
    opacity: f32 = 1.0,

    pub fn init(
        rs: Renderstate,
        wo: Vec4f,
        albedo: Vec4f,
        alpha: Vec2f,
        ior: f32,
        ior_outer: f32,
        ior_medium: f32,
        metallic: f32,
        volumetric: bool,
    ) Sample {
        const color = @as(Vec4f, @splat(1.0 - metallic)) * albedo;
        const reg_alpha = rs.regularizeAlpha(alpha);

        var super = Base.init(rs, wo, color, reg_alpha, 0.0);
        super.properties.can_evaluate = ior != ior_medium;
        super.properties.volumetric = volumetric;

        const f0 = fresnel.Schlick.IorToF0(ior, ior_outer);

        return .{
            .super = super,
            .f0 = math.lerp(@as(Vec4f, @splat(f0)), albedo, @as(Vec4f, @splat(metallic))),
            .ior = .{ .eta_t = ior, .eta_i = ior_medium },
            .metallic = metallic,
        };
    }

    pub fn setTranslucency(self: *Sample, color: Vec4f, thickness: f32, attenuation_distance: f32, transparency: f32) void {
        self.super.properties.translucent = true;
        self.super.properties.volumetric = false;
        self.super.thickness = thickness;
        self.absorption_coef = ccoef.attenuationCoefficient(color, attenuation_distance);
        self.opacity = 1.0 - transparency;
    }

    pub fn evaluate(self: *const Sample, wi: Vec4f, split: bool) bxdf.Result {
        if (self.super.properties.volumetric) {
            return self.volumetricEvaluate(wi, split);
        }

        const wo = self.super.wo;

        const op = self.opacity;
        const th = self.super.thickness;
        const translucent = th > 0.0;

        if (translucent) {
            if (!self.super.sameHemisphere(wi)) {
                const n_dot_wi = self.super.frame.clampAbsNdot(wi);
                const n_dot_wo = self.super.frame.clampAbsNdot(wo);

                const f = diffuseFresnelHack(n_dot_wi, n_dot_wo, self.f0[0]);

                const approx_dist = th / n_dot_wi;
                const attenuation = inthlp.attenuation3(self.absorption_coef, approx_dist);

                const pdf = n_dot_wi * ((1.0 - op) * math.pi_inv);

                return bxdf.Result.init(@as(Vec4f, @splat(pdf * (1.0 - f))) * (attenuation * self.super.albedo), pdf);
            }
        } else if (!self.super.sameHemisphere(wo)) {
            return bxdf.Result.empty();
        }

        const h = math.normalize3(wo + wi);
        const wo_dot_h = math.safe.clampDot(wo, h);

        var base_result = if (1.0 == self.metallic)
            self.pureGlossEvaluate(wi, wo, h, wo_dot_h)
        else
            self.baseEvaluate(wi, wo, h, wo_dot_h);

        if (translucent) {
            base_result.mulAssignPdf(op);
        }

        if (self.coating.thickness > 0.0) {
            const coating = self.coating.evaluate(wi, wo, h, wo_dot_h, self.super.avoidCaustics());
            const pdf = coating.f * coating.pdf + (1.0 - coating.f) * base_result.pdf();
            return bxdf.Result.init(coating.reflection + coating.attenuation * base_result.reflection, pdf);
        }

        return base_result;
    }

    pub fn sample(self: *const Sample, sampler: *Sampler, split: bool, buffer: *bxdf.Samples) []bxdf.Sample {
        const th = self.super.thickness;
        if (th > 0.0) {
            var result = &buffer[0];

            result.split_weight = 1.0;
            result.wavelength = 0.0;

            const op = self.opacity;
            const tr = 1.0 - op;

            const s3 = sampler.sample3D();
            const p = s3[0];
            if (p < tr) {
                const frame = self.super.frame;
                const n_dot_wi = diffuse.Lambert.reflect(self.super.albedo, frame, sampler, result);
                const n_dot_wo = frame.clampAbsNdot(self.super.wo);

                const f = diffuseFresnelHack(n_dot_wi, n_dot_wo, self.f0[0]);

                const approx_dist = th / n_dot_wi;
                const attenuation = inthlp.attenuation3(self.absorption_coef, approx_dist);

                result.wi = -result.wi;
                result.reflection *= @as(Vec4f, @splat(tr * n_dot_wi * (1.0 - f))) * attenuation;
                result.pdf *= tr;
            } else {
                const xi = Vec2f{ s3[1], s3[2] };

                if (p < tr + 0.5 * op) {
                    _ = self.diffuseSample(xi, result);
                } else {
                    _ = self.glossSample(xi, result);
                }

                result.pdf *= op;
            }

            return buffer[0..1];
        } else {
            if (self.super.properties.volumetric) {
                return self.volumetricSample(sampler, split, buffer);
            }

            if (!self.super.sameHemisphere(self.super.wo)) {
                return buffer[0..0];
            }

            var result = &buffer[0];

            result.split_weight = 1.0;
            result.wavelength = 0.0;

            if (self.coating.thickness > 0.0) {
                self.coatingSample(sampler, result);
            } else {
                self.baseSample(sampler, result);
            }

            return buffer[0..1];
        }
    }

    fn baseEvaluate(self: *const Sample, wi: Vec4f, wo: Vec4f, h: Vec4f, wo_dot_h: f32) bxdf.Result {
        const frame = self.super.frame;
        const alpha = self.super.alpha;

        const n_dot_wi = frame.clampNdot(wi);
        const n_dot_wo = frame.clampAbsNdot(wo);

        const albedo = @as(Vec4f, @splat(self.opacity)) * self.super.albedo;
        const d = diffuse.Micro.reflection(albedo, self.f0, n_dot_wi, n_dot_wo, alpha[1]);

        if (self.super.avoidCaustics() and alpha[1] <= ggx.Min_alpha) {
            return bxdf.Result.init(@as(Vec4f, @splat(n_dot_wi)) * d.reflection, d.pdf());
        }

        const schlick = fresnel.Schlick.init(self.f0);

        var gg = ggx.Aniso.reflection(
            wi,
            wo,
            h,
            n_dot_wi,
            n_dot_wo,
            wo_dot_h,
            alpha,
            schlick,
            frame,
        );

        const mms = ggx.dspbrMicroEc(self.f0, n_dot_wi, n_dot_wo, alpha[1]);
        const pdf = 0.5 * (d.pdf() + gg.pdf());
        return bxdf.Result.init(@as(Vec4f, @splat(n_dot_wi)) * (d.reflection + gg.reflection + mms), pdf);
    }

    fn pureGlossEvaluate(self: *const Sample, wi: Vec4f, wo: Vec4f, h: Vec4f, wo_dot_h: f32) bxdf.Result {
        const alpha = self.super.alpha;

        if (self.super.avoidCaustics() and alpha[1] <= ggx.Min_alpha) {
            return bxdf.Result.empty();
        }

        const frame = self.super.frame;

        const n_dot_wi = frame.clampNdot(wi);

        if (self.super.properties.flakes) {
            const cos_cone = alpha[0];
            const r = math.reflect3(frame.z, wo);
            const f = if (math.dot3(wi, r) > cos_cone) 1.0 / math.solidAngleOfCone(cos_cone) else 0.0;

            return bxdf.Result.init(@as(Vec4f, @splat(n_dot_wi * f)) * self.f0, f);
        }

        const n_dot_wo = frame.clampAbsNdot(wo);

        const schlick = fresnel.Schlick.init(self.f0);

        var gg = ggx.Aniso.reflection(
            wi,
            wo,
            h,
            n_dot_wi,
            n_dot_wo,
            wo_dot_h,
            alpha,
            schlick,
            frame,
        );

        const mms = ggx.dspbrMicroEc(self.f0, n_dot_wi, n_dot_wo, alpha[1]);
        return bxdf.Result.init(@as(Vec4f, @splat(n_dot_wi)) * (gg.reflection + mms), gg.pdf());
    }

    fn baseSample(self: *const Sample, sampler: *Sampler, result: *bxdf.Sample) void {
        if (1.0 == self.metallic) {
            const xi = sampler.sample2D();
            _ = self.pureGlossSample(xi, result);
        } else {
            const s3 = sampler.sample3D();
            const p = s3[0];
            const xi = Vec2f{ s3[1], s3[2] };
            if (p < 0.5) {
                _ = self.diffuseSample(xi, result);
            } else {
                _ = self.glossSample(xi, result);
            }
        }
    }

    fn coatingSample(self: *const Sample, sampler: *Sampler, result: *bxdf.Sample) void {
        var n_dot_h: f32 = undefined;
        const micro = self.coating.sample(self.super.wo, sampler.sample2D(), &n_dot_h);
        const f = micro.n_dot_wi;

        const s3 = sampler.sample3D();
        const p = s3[0];
        if (p <= f) {
            self.coatingReflect(micro.h, f, n_dot_h, micro.h_dot_wi, result);
        } else {
            const xi = Vec2f{ s3[1], s3[2] };

            if (1.0 == self.metallic) {
                self.coatingBaseSample(pureGlossSample, xi, f, result);
            } else {
                const p1 = (p - f) / (1.0 - f);
                if (p1 < 0.5) {
                    self.coatingBaseSample(diffuseSample, xi, f, result);
                } else {
                    self.coatingBaseSample(glossSample, xi, f, result);
                }
            }
        }
    }

    fn diffuseSample(self: *const Sample, xi: Vec2f, result: *bxdf.Sample) ggx.Micro {
        const wo = self.super.wo;
        const frame = self.super.frame;
        const alpha = self.super.alpha;

        const n_dot_wo = frame.clampAbsNdot(wo);

        const albedo = @as(Vec4f, @splat(self.opacity)) * self.super.albedo;
        const micro = diffuse.Micro.reflect(
            albedo,
            self.f0,
            wo,
            n_dot_wo,
            frame,
            alpha[1],
            xi,
            result,
        );

        if (self.super.avoidCaustics() and alpha[1] <= ggx.Min_alpha) {
            result.reflection *= @splat(micro.n_dot_wi);
            return micro;
        }

        const schlick = fresnel.Schlick.init(self.f0);

        var gg = ggx.Aniso.reflection(
            result.wi,
            wo,
            micro.h,
            micro.n_dot_wi,
            n_dot_wo,
            micro.h_dot_wi,
            alpha,
            schlick,
            frame,
        );

        const mms = ggx.dspbrMicroEc(self.f0, micro.n_dot_wi, n_dot_wo, alpha[1]);

        result.reflection = @as(Vec4f, @splat(micro.n_dot_wi)) * (result.reflection + gg.reflection + mms);
        result.pdf = 0.5 * (result.pdf + gg.pdf());

        return micro;
    }

    fn glossSample(self: *const Sample, xi: Vec2f, result: *bxdf.Sample) ggx.Micro {
        const wo = self.super.wo;
        const frame = self.super.frame;
        const alpha = self.super.alpha;

        const n_dot_wo = frame.clampAbsNdot(wo);

        const schlick = fresnel.Schlick.init(self.f0);

        const micro = ggx.Aniso.reflect(wo, n_dot_wo, alpha, xi, schlick, frame, result);

        const mms = ggx.dspbrMicroEc(self.f0, micro.n_dot_wi, n_dot_wo, alpha[1]);

        const albedo = @as(Vec4f, @splat(self.opacity)) * self.super.albedo;
        const d = diffuse.Micro.reflection(albedo, self.f0, micro.n_dot_wi, n_dot_wo, alpha[1]);

        result.reflection = @as(Vec4f, @splat(micro.n_dot_wi)) * (result.reflection + mms + d.reflection);
        result.pdf = 0.5 * (result.pdf + d.pdf());

        return micro;
    }

    fn pureGlossSample(self: *const Sample, xi: Vec2f, result: *bxdf.Sample) ggx.Micro {
        const wo = self.super.wo;
        const frame = self.super.frame;
        const alpha = self.super.alpha;

        if (self.super.properties.flakes) {
            const h = math.reflect3(frame.z, wo);
            const tb = math.orthonormalBasis3(h);

            const cos_cone = alpha[0];
            const wi = math.smpl.orientedConeUniform(xi, cos_cone, tb[0], tb[1], h);
            const wi_dot_h = math.safe.clampDot(wi, h);

            const f = if (wi_dot_h > cos_cone) 1.0 / math.solidAngleOfCone(cos_cone) else 0.0;

            const n_dot_wi = frame.clampNdot(wi);

            result.reflection = @as(Vec4f, @splat(n_dot_wi * f)) * self.f0;
            result.wi = wi;
            result.pdf = f;
            result.class = .{ .glossy = true, .reflection = true };

            return .{ .h = h, .n_dot_wi = n_dot_wi, .h_dot_wi = wi_dot_h };
        } else {
            const n_dot_wo = frame.clampAbsNdot(wo);

            const schlick = fresnel.Schlick.init(self.f0);

            const micro = ggx.Aniso.reflect(wo, n_dot_wo, alpha, xi, schlick, frame, result);

            const mms = ggx.dspbrMicroEc(self.f0, micro.n_dot_wi, n_dot_wo, alpha[1]);
            result.reflection = @as(Vec4f, @splat(micro.n_dot_wi)) * (result.reflection + mms);

            return micro;
        }
    }

    fn coatingReflect(self: *const Sample, h: Vec4f, f: f32, n_dot_h: f32, h_dot_wi: f32, result: *bxdf.Sample) void {
        const wo = self.super.wo;
        const n_dot_wo = math.safe.clampAbsDot(self.coating.n, wo);

        const coating_attenuation = self.coating.reflect(
            wo,
            h,
            n_dot_wo,
            n_dot_h,
            h_dot_wi,
            result,
        );

        const base_result = if (1.0 == self.metallic)
            self.pureGlossEvaluate(result.wi, wo, h, h_dot_wi)
        else
            self.baseEvaluate(result.wi, wo, h, h_dot_wi);

        result.reflection = (result.reflection * @as(Vec4f, @splat(f))) + coating_attenuation * base_result.reflection;
        result.pdf = f * result.pdf + (1.0 - f) * base_result.pdf();
    }

    const SampleFunc = *const fn (self: *const Sample, xi: Vec2f, result: *bxdf.Sample) ggx.Micro;

    fn coatingBaseSample(
        self: *const Sample,
        sampleFunc: SampleFunc,
        xi: Vec2f,
        f: f32,
        result: *bxdf.Sample,
    ) void {
        const micro = sampleFunc(self, xi, result);

        const coating = self.coating.evaluate(
            result.wi,
            self.super.wo,
            micro.h,
            micro.h_dot_wi,
            self.super.avoidCaustics(),
        );

        result.reflection = coating.attenuation * result.reflection + coating.reflection;
        result.pdf = (1.0 - f) * result.pdf + f * coating.pdf;
    }

    fn diffuseFresnelHack(n_dot_wi: f32, n_dot_wo: f32, f0: f32) f32 {
        return fresnel.schlick1(math.min(n_dot_wi, n_dot_wo), f0);
    }

    fn volumetricEvaluate(self: *const Sample, wi: Vec4f, split: bool) bxdf.Result {
        const quo_ior = self.ior;
        if (quo_ior.eta_i == quo_ior.eta_t) {
            return bxdf.Result.empty();
        }

        const wo = self.super.wo;
        const alpha = self.super.alpha;
        const frame = self.super.frame;

        if (!self.super.sameHemisphere(wo)) {
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
            const n_dot_h = math.saturate(frame.nDot(h));

            const schlick = fresnel.Schlick.init(self.f0);

            const gg = ggx.Iso.refractionF(
                n_dot_wi,
                n_dot_wo,
                wi_dot_h,
                wo_dot_h,
                n_dot_h,
                alpha[0],
                ior,
                schlick,
            );

            const comp = ggx.ilmEpDielectric(n_dot_wo, alpha[0], self.f0[0]);

            const coat_n_dot_wo = math.safe.clampAbsDot(self.coating.n, wo);
            const attenuation = self.coating.singleAttenuation(coat_n_dot_wo);

            const split_pdf = if (split) 1.0 else gg.f[0];

            return bxdf.Result.init(
                @as(Vec4f, @splat(math.min(n_dot_wi, n_dot_wo) * comp)) * attenuation * gg.r.reflection,
                split_pdf * gg.r.pdf(),
            );
        }

        const h = math.normalize3(wo + wi);
        const wo_dot_h = math.safe.clampDot(wo, h);
        const n_dot_wi = frame.clampNdot(wi);
        const n_dot_wo = frame.clampAbsNdot(wo);

        if (self.super.avoidCaustics() and alpha[1] <= ggx.Min_alpha) {
            return bxdf.Result.empty();
        }

        const schlick = fresnel.Schlick.init(self.f0);

        var gg = ggx.Aniso.reflectionF(
            wi,
            wo,
            h,
            n_dot_wi,
            n_dot_wo,
            wo_dot_h,
            alpha,
            schlick,
            frame,
        );

        const coated = self.coating.thickness > 0.0;

        const mms = ggx.dspbrMicroEc(self.f0, n_dot_wi, n_dot_wo, alpha[1]);
        const base_reflection = @as(Vec4f, @splat(n_dot_wi)) * (gg.r.reflection + mms);
        const split_pdf = if (split and !coated) 1.0 else gg.f[0];
        const base_pdf = split_pdf * gg.r.pdf();

        if (coated) {
            const coating = self.coating.evaluate(wi, wo, h, wo_dot_h, self.super.avoidCaustics());
            const pdf = coating.f * coating.pdf + (1.0 - coating.f) * base_pdf;
            return bxdf.Result.init(coating.reflection + coating.attenuation * base_reflection, pdf);
        }

        return bxdf.Result.init(base_reflection, base_pdf);
    }

    fn volumetricSample(self: Sample, sampler: *Sampler, split: bool, buffer: *bxdf.Samples) []bxdf.Sample {
        if (self.coating.thickness > 0.0) {
            const result = &buffer[0];

            self.coatedVolumetricSample(sampler, result);
            return buffer[0..1];
        }

        const wo = self.super.wo;
        const quo_ior = self.ior;
        if (math.eq(quo_ior.eta_i, quo_ior.eta_t, 2.e-7)) {
            var result = &buffer[0];

            result.reflection = @splat(1.0);
            result.wi = -wo;
            result.pdf = 1.0;
            result.split_weight = 1.0;
            result.wavelength = 0.0;
            result.class = .{ .specular = true, .transmission = true };
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

        var f: f32 = undefined;
        var wi_dot_h: f32 = undefined;
        if (sint2 >= 1.0) {
            f = 1.0;
            wi_dot_h = 0.0;
        } else {
            wi_dot_h = @sqrt(1.0 - sint2);
            const cos_x = if (ior.eta_i > ior.eta_t) wi_dot_h else wo_dot_h;
            f = fresnel.schlick1(cos_x, self.f0[0]);
        }

        if (split and same_side) {
            {
                const n_dot_wi = ggx.Aniso.reflectNoFresnel(
                    wo,
                    h,
                    n_dot_wo,
                    n_dot_h,
                    wo_dot_h,
                    alpha,
                    frame,
                    &buffer[0],
                );

                const mms = ggx.dspbrMicroEc(self.f0, n_dot_wi, n_dot_wo, alpha[1]);
                const reflection = @as(Vec4f, @splat(n_dot_wi)) * (buffer[0].reflection + mms);

                buffer[0].reflection = reflection;
                buffer[0].split_weight = f;
                buffer[0].wavelength = 0.0;
            }

            {
                const r_wo_dot_h = -wo_dot_h;
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
                    &buffer[1],
                );

                const omf = 1.0 - f;
                buffer[1].reflection *= @splat(n_dot_wi);
                buffer[1].split_weight = omf;
                buffer[1].wavelength = 0.0;
            }

            return buffer[0..2];
        } else {
            var result = &buffer[0];

            result.split_weight = 1.0;
            result.wavelength = 0.0;

            const p = s3[0];
            if (same_side) {
                if (p <= f) {
                    const n_dot_wi = ggx.Aniso.reflectNoFresnel(
                        wo,
                        h,
                        n_dot_wo,
                        n_dot_h,
                        wo_dot_h,
                        alpha,
                        frame,
                        result,
                    );

                    const mms = ggx.dspbrMicroEc(self.f0, n_dot_wi, n_dot_wo, alpha[1]);
                    const reflection = @as(Vec4f, @splat(n_dot_wi)) * (@as(Vec4f, @splat(f)) * result.reflection + mms);

                    result.reflection = reflection;
                    result.pdf *= f;
                } else {
                    const r_wo_dot_h = -wo_dot_h;
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
                        result,
                    );

                    const omf = 1.0 - f;
                    result.reflection *= @splat(omf * n_dot_wi);
                    result.pdf *= omf;
                }
            } else {
                const ep = ggx.ilmEpDielectric(n_dot_wo, alpha[1], self.f0[0]);

                if (p <= f) {
                    const n_dot_wi = ggx.Aniso.reflectNoFresnel(
                        wo,
                        h,
                        n_dot_wo,
                        n_dot_h,
                        wo_dot_h,
                        alpha,
                        frame,
                        result,
                    );

                    result.reflection *= @splat(f * n_dot_wi * ep);
                    result.pdf *= f;
                } else {
                    const r_wo_dot_h = wo_dot_h;
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
                        result,
                    );

                    const omf = 1.0 - f;
                    result.reflection *= @splat(omf * n_dot_wi * ep);
                    result.pdf *= omf;
                }
            }

            return buffer[0..1];
        }
    }

    fn coatedVolumetricSample(self: Sample, sampler: *Sampler, result: *bxdf.Sample) void {
        result.split_weight = 1.0;
        result.wavelength = 0.0;

        const wo = self.super.wo;
        const quo_ior = self.ior;
        if (math.eq(quo_ior.eta_i, quo_ior.eta_t, 2.e-7)) {
            result.reflection = @splat(1.0);
            result.wi = -wo;
            result.pdf = 1.0;
            result.class = .{ .specular = true, .transmission = true };
            return;
        }

        const alpha = self.super.alpha;
        const same_side = self.super.sameHemisphere(wo);
        const frame = self.super.frame.swapped(same_side);
        const ior = quo_ior.swapped(same_side);

        const s3 = sampler.sample3D();
        const xi = Vec2f{ s3[1], s3[2] };
        var p = s3[0];

        if (same_side) {
            var coat_n_dot_h: f32 = undefined;
            const micro = self.coating.sample(self.super.wo, xi, &coat_n_dot_h);
            const cf = micro.n_dot_wi;

            if (p <= cf) {
                self.coatingReflect(micro.h, cf, coat_n_dot_h, micro.h_dot_wi, result);
            } else {
                const omcf = 1.0 - cf;
                p = (p - cf) / omcf;

                var n_dot_h: f32 = undefined;
                const h = ggx.Aniso.sample(wo, alpha, sampler.sample2D(), frame, &n_dot_h);

                const n_dot_wo = frame.clampAbsNdot(wo);
                const wo_dot_h = math.safe.clampDot(wo, h);
                const eta = ior.eta_i / ior.eta_t;
                const sint2 = (eta * eta) * (1.0 - wo_dot_h * wo_dot_h);

                var f: f32 = undefined;
                var wi_dot_h: f32 = undefined;
                if (sint2 >= 1.0) {
                    f = 1.0;
                    wi_dot_h = 0.0;
                } else {
                    wi_dot_h = @sqrt(1.0 - sint2);
                    const cos_x = if (ior.eta_i > ior.eta_t) wi_dot_h else wo_dot_h;
                    f = fresnel.schlick1(cos_x, self.f0[0]);
                }

                if (p <= f) {
                    const n_dot_wi = ggx.Aniso.reflectNoFresnel(
                        wo,
                        h,
                        n_dot_wo,
                        n_dot_h,
                        wo_dot_h,
                        alpha,
                        frame,
                        result,
                    );

                    const mms = ggx.dspbrMicroEc(self.f0, n_dot_wi, n_dot_wo, alpha[1]);
                    const reflection = @as(Vec4f, @splat(n_dot_wi)) * (@as(Vec4f, @splat(f)) * result.reflection + mms);

                    const coating = self.coating.evaluate(
                        result.wi,
                        self.super.wo,
                        h,
                        wo_dot_h,
                        self.super.avoidCaustics(),
                    );

                    result.reflection = coating.attenuation * reflection + coating.reflection;
                    result.pdf = (1.0 - cf) * (f * result.pdf) + cf * coating.pdf;
                } else {
                    const r_wo_dot_h = -wo_dot_h;
                    const n_dot_wi = ggx.Iso.refractNoFresnel(
                        wo,
                        h,
                        n_dot_wo,
                        n_dot_h,
                        -wi_dot_h,
                        r_wo_dot_h,
                        alpha[1],
                        ior,
                        frame,
                        result,
                    );

                    const coat_n_dot_wo = math.safe.clampAbsDot(self.coating.n, wo);
                    const attenuation = self.coating.singleAttenuation(coat_n_dot_wo);

                    const omf = 1.0 - f;
                    result.reflection *= @as(Vec4f, @splat(omf * n_dot_wi)) * attenuation;
                    result.pdf *= omf * omcf;
                }
            }
        } else {
            var n_dot_h: f32 = undefined;
            const h = ggx.Aniso.sample(wo, alpha, xi, frame, &n_dot_h);

            const n_dot_wo = frame.clampAbsNdot(wo);
            const wo_dot_h = math.safe.clampDot(wo, h);
            const eta = ior.eta_i / ior.eta_t;
            const sint2 = (eta * eta) * (1.0 - wo_dot_h * wo_dot_h);

            var f: f32 = undefined;
            var wi_dot_h: f32 = undefined;
            if (sint2 >= 1.0) {
                f = 1.0;
                wi_dot_h = 0.0;
            } else {
                wi_dot_h = @sqrt(1.0 - sint2);
                const cos_x = if (ior.eta_i > ior.eta_t) wi_dot_h else wo_dot_h;
                f = fresnel.schlick1(cos_x, self.f0[0]);
            }

            const ep = ggx.ilmEpDielectric(n_dot_wo, alpha[1], self.f0[0]);

            if (p <= f) {
                const n_dot_wi = ggx.Aniso.reflectNoFresnel(
                    wo,
                    h,
                    n_dot_wo,
                    n_dot_h,
                    wo_dot_h,
                    alpha,
                    frame,
                    result,
                );

                result.reflection *= @splat(f * n_dot_wi * ep);
                result.pdf *= f;
            } else {
                const r_wo_dot_h = wo_dot_h;
                const n_dot_wi = ggx.Iso.refractNoFresnel(
                    wo,
                    h,
                    n_dot_wo,
                    n_dot_h,
                    -wi_dot_h,
                    r_wo_dot_h,
                    alpha[1],
                    ior,
                    frame,
                    result,
                );

                const coat_n_dot_wo = math.safe.clampAbsDot(self.coating.n, wo);
                const attenuation = self.coating.singleAttenuation(coat_n_dot_wo);

                const omf = 1.0 - f;
                result.reflection *= @as(Vec4f, @splat(omf * n_dot_wi * ep)) * attenuation;
                result.pdf *= omf;
            }
        }
    }
};
