const sample = @import("../sample_base.zig");
const Base = sample.SampleBase;
const IoR = sample.IoR;
const Coating = @import("coating.zig").Coating;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const ccoef = @import("../collision_coefficients.zig");
const diffuse = @import("../diffuse.zig");
const fresnel = @import("../fresnel.zig");
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

    coating: Coating = .{},

    f0: Vec4f,
    translucent_color: Vec4f = undefined,
    attenuation: Vec4f = undefined,

    ior: IoR,

    metallic: f32,
    thickness: f32 = 0.0,
    transparency: f32 = undefined,

    volumetric: bool,
    flakes: bool = false,

    pub fn init(
        rs: Renderstate,
        wo: Vec4f,
        albedo: Vec4f,
        radiance: Vec4f,
        alpha: Vec2f,
        ior: f32,
        ior_outer: f32,
        ior_medium: f32,
        metallic: f32,
        volumetric: bool,
    ) Sample {
        const color = @splat(4, 1.0 - metallic) * albedo;

        var super = Base.init(rs, wo, color, radiance, alpha);
        super.properties.can_evaluate = ior != ior_medium;

        const f0 = fresnel.Schlick.F0(ior, ior_outer);

        return .{
            .super = super,
            .f0 = math.lerp(@splat(4, f0), albedo, metallic),
            .metallic = metallic,
            .ior = .{ .eta_t = ior, .eta_i = ior_medium },
            .volumetric = volumetric,
        };
    }

    pub fn setTranslucency(self: *Sample, color: Vec4f, thickness: f32, attenuation_distance: f32, transparency: f32) void {
        self.super.properties.translucent = true;
        self.super.albedo = @splat(4, 1.0 - transparency) * color;
        self.translucent_color = color;
        self.attenuation = ccoef.attenuationCoefficient(color, attenuation_distance);
        self.thickness = thickness;
        self.transparency = transparency;
        self.volumetric = false;
    }

    pub fn evaluate(self: *const Sample, wi: Vec4f) bxdf.Result {
        if (self.volumetric) {
            return self.volumetricEvaluate(wi);
        }

        const wo = self.super.wo;

        const tr = self.transparency;
        const th = self.thickness;
        const translucent = th > 0.0;

        if (translucent) {
            if (!self.super.sameHemisphere(wi)) {
                const n_dot_wi = self.super.frame.clampAbsNdot(wi);
                const n_dot_wo = self.super.frame.clampAbsNdot(wo);

                const f = diffuseFresnelHack(n_dot_wi, n_dot_wo, self.f0[0]);

                const approx_dist = th / n_dot_wi;
                const attenuation = inthlp.attenuation3(self.attenuation, approx_dist);

                const pdf = n_dot_wi * (tr * math.pi_inv);

                return bxdf.Result.init(@splat(4, pdf * (1.0 - f)) * (attenuation * self.translucent_color), pdf);
            }
        } else if (!self.super.sameHemisphere(wo)) {
            return bxdf.Result.empty();
        }

        const h = math.normalize3(wo + wi);
        const wo_dot_h = hlp.clampDot(wo, h);

        var base_result = if (1.0 == self.metallic)
            self.pureGlossEvaluate(wi, wo, h, wo_dot_h)
        else
            self.baseEvaluate(wi, wo, h, wo_dot_h);

        if (translucent) {
            base_result.mulAssignPdf(1.0 - tr);
        }

        if (self.coating.thickness > 0.0) {
            const coating = self.coating.evaluate(wi, wo, h, wo_dot_h, self.super.avoidCaustics());
            const pdf = coating.f * coating.pdf + (1.0 - coating.f) * base_result.pdf();
            return bxdf.Result.init(coating.reflection + coating.attenuation * base_result.reflection, pdf);
        }

        return base_result;
    }

    pub fn sample(self: *const Sample, sampler: *Sampler) bxdf.Sample {
        var result = bxdf.Sample{ .wavelength = 0.0 };

        const th = self.thickness;
        if (th > 0.0) {
            const tr = self.transparency;

            const s3 = sampler.sample3D();
            const p = s3[0];
            if (p < tr) {
                const frame = self.super.frame;
                const n_dot_wi = diffuse.Lambert.reflect(self.translucent_color, frame, sampler, &result);
                const n_dot_wo = frame.clampAbsNdot(self.super.wo);

                const f = diffuseFresnelHack(n_dot_wi, n_dot_wo, self.f0[0]);

                const approx_dist = th / n_dot_wi;
                const attenuation = inthlp.attenuation3(self.attenuation, approx_dist);

                result.wi = -result.wi;
                result.reflection *= @splat(4, tr * n_dot_wi * (1.0 - f)) * attenuation;
                result.pdf *= tr;
            } else {
                const o = 1.0 - tr;

                const xi = Vec2f{ s3[1], s3[2] };

                if (p < tr + 0.5 * o) {
                    self.diffuseSample(xi, &result);
                } else {
                    self.glossSample(xi, &result);
                }

                result.pdf *= o;
            }
        } else {
            if (self.volumetric) {
                self.volumetricSample(sampler, &result);
                return result;
            }

            if (!self.super.sameHemisphere(self.super.wo)) {
                return result;
            }

            if (self.coating.thickness > 0.0) {
                self.coatingSample(sampler, &result);
            } else {
                self.baseSample(sampler, &result);
            }
        }

        return result;
    }

    fn baseEvaluate(self: *const Sample, wi: Vec4f, wo: Vec4f, h: Vec4f, wo_dot_h: f32) bxdf.Result {
        const frame = self.super.frame;
        const alpha = self.super.alpha;

        const n_dot_wi = frame.clampNdot(wi);
        const n_dot_wo = frame.clampAbsNdot(wo);

        const d = diffuse.Micro.reflection(self.super.albedo, self.f0, n_dot_wi, n_dot_wo, alpha[1]);

        if (self.super.avoidCaustics() and alpha[1] <= ggx.Min_alpha) {
            return bxdf.Result.init(@splat(4, n_dot_wi) * d.reflection, d.pdf());
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
        return bxdf.Result.init(@splat(4, n_dot_wi) * (d.reflection + gg.reflection + mms), pdf);
    }

    fn pureGlossEvaluate(self: *const Sample, wi: Vec4f, wo: Vec4f, h: Vec4f, wo_dot_h: f32) bxdf.Result {
        const alpha = self.super.alpha;

        if (self.super.avoidCaustics() and alpha[1] <= ggx.Min_alpha) {
            return bxdf.Result.empty();
        }

        const frame = self.super.frame;

        const n_dot_wi = frame.clampNdot(wi);

        if (self.flakes) {
            const cos_cone = alpha[0];
            const r = math.reflect3(frame.n, wo);
            const f = if (math.dot3(wi, r) > cos_cone) 1.0 / math.solidAngleCone(cos_cone) else 0.0;

            return bxdf.Result.init(@splat(4, n_dot_wi * f) * self.f0, f);
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
        return bxdf.Result.init(@splat(4, n_dot_wi) * (gg.reflection + mms), gg.pdf());
    }

    fn baseSample(self: *const Sample, sampler: *Sampler, result: *bxdf.Sample) void {
        if (1.0 == self.metallic) {
            const xi = sampler.sample2D();
            self.pureGlossSample(xi, result);
        } else {
            const s3 = sampler.sample3D();
            const p = s3[0];
            const xi = Vec2f{ s3[1], s3[2] };
            if (p < 0.5) {
                self.diffuseSample(xi, result);
            } else {
                self.glossSample(xi, result);
            }
        }
    }

    fn coatingSample(self: *const Sample, sampler: *Sampler, result: *bxdf.Sample) void {
        var n_dot_h: f32 = undefined;
        const f = self.coating.sample(self.super.wo, sampler.sample2D(), &n_dot_h, result);

        const s3 = sampler.sample3D();
        const p = s3[0];
        if (p <= f) {
            self.coatingReflect(f, n_dot_h, result);
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

    fn diffuseSample(self: *const Sample, xi: Vec2f, result: *bxdf.Sample) void {
        const wo = self.super.wo;
        const frame = self.super.frame;
        const alpha = self.super.alpha;

        const n_dot_wo = frame.clampAbsNdot(wo);

        const n_dot_wi = diffuse.Micro.reflect(
            self.super.albedo,
            self.f0,
            wo,
            n_dot_wo,
            frame,
            alpha[1],
            xi,
            result,
        );

        if (self.super.avoidCaustics() and alpha[1] <= ggx.Min_alpha) {
            result.reflection *= @splat(4, n_dot_wi);
            return;
        }

        const schlick = fresnel.Schlick.init(self.f0);

        var gg = ggx.Aniso.reflection(
            result.wi,
            wo,
            result.h,
            n_dot_wi,
            n_dot_wo,
            result.h_dot_wi,
            alpha,
            schlick,
            frame,
        );

        const mms = ggx.dspbrMicroEc(self.f0, n_dot_wi, n_dot_wo, alpha[1]);

        result.reflection = @splat(4, n_dot_wi) * (result.reflection + gg.reflection + mms);
        result.pdf = 0.5 * (result.pdf + gg.pdf());
    }

    fn glossSample(self: *const Sample, xi: Vec2f, result: *bxdf.Sample) void {
        const wo = self.super.wo;
        const frame = self.super.frame;
        const alpha = self.super.alpha;

        const n_dot_wo = frame.clampAbsNdot(wo);

        const schlick = fresnel.Schlick.init(self.f0);

        const n_dot_wi = ggx.Aniso.reflect(wo, n_dot_wo, alpha, xi, schlick, frame, result);

        const mms = ggx.dspbrMicroEc(self.f0, n_dot_wi, n_dot_wo, alpha[1]);

        const d = diffuse.Micro.reflection(self.super.albedo, self.f0, n_dot_wi, n_dot_wo, alpha[1]);

        result.reflection = @splat(4, n_dot_wi) * (result.reflection + mms + d.reflection);
        result.pdf = 0.5 * (result.pdf + d.pdf());
    }

    fn pureGlossSample(self: *const Sample, xi: Vec2f, result: *bxdf.Sample) void {
        const wo = self.super.wo;
        const frame = self.super.frame;
        const alpha = self.super.alpha;

        if (self.flakes) {
            const n = frame.n;
            const h = math.reflect3(n, wo);
            const tb = math.orthonormalBasis3(h);

            const cos_cone = alpha[0];
            const wi = math.smpl.orientedConeUniform(xi, cos_cone, tb[0], tb[1], h);

            const wi_dot_h = hlp.clampDot(wi, h);

            const f = if (wi_dot_h > cos_cone) 1.0 / math.solidAngleCone(cos_cone) else 0.0;

            const n_dot_wi = frame.clampNdot(wi);

            result.reflection = @splat(4, n_dot_wi * f) * self.f0;
            result.wi = wi;
            result.h = h;
            result.h_dot_wi = wi_dot_h;
            result.pdf = f;
            result.class = .{ .glossy = true, .reflection = true };
        } else {
            const n_dot_wo = frame.clampAbsNdot(wo);

            const schlick = fresnel.Schlick.init(self.f0);

            const n_dot_wi = ggx.Aniso.reflect(wo, n_dot_wo, alpha, xi, schlick, frame, result);

            const mms = ggx.dspbrMicroEc(self.f0, n_dot_wi, n_dot_wo, alpha[1]);
            result.reflection = @splat(4, n_dot_wi) * (result.reflection + mms);
        }
    }

    fn coatingReflect(self: *const Sample, f: f32, n_dot_h: f32, result: *bxdf.Sample) void {
        const wo = self.super.wo;
        const n_dot_wo = self.coating.frame.clampAbsNdot(self.super.wo);

        var coating_attenuation: Vec4f = undefined;
        self.coating.reflect(
            wo,
            result.h,
            n_dot_wo,
            n_dot_h,
            result.h_dot_wi,
            result.h_dot_wi,
            &coating_attenuation,
            result,
        );

        var base_result = if (1.0 == self.metallic)
            self.pureGlossEvaluate(result.wi, wo, result.h, result.h_dot_wi)
        else
            self.baseEvaluate(result.wi, wo, result.h, result.h_dot_wi);

        result.reflection = result.reflection + coating_attenuation * base_result.reflection;
        result.pdf = f * result.pdf + (1.0 - f) * base_result.pdf();
    }

    const SampleFunc = *const fn (self: *const Sample, xi: Vec2f, result: *bxdf.Sample) void;

    fn coatingBaseSample(
        self: *const Sample,
        sampleFunc: SampleFunc,
        xi: Vec2f,
        f: f32,
        result: *bxdf.Sample,
    ) void {
        sampleFunc(self, xi, result);

        const coating = self.coating.evaluate(
            result.wi,
            self.super.wo,
            result.h,
            result.h_dot_wi,
            self.super.avoidCaustics(),
        );

        result.reflection = coating.attenuation * result.reflection + coating.reflection;
        result.pdf = (1.0 - f) * result.pdf + f * coating.pdf;
    }

    fn diffuseFresnelHack(n_dot_wi: f32, n_dot_wo: f32, f0: f32) f32 {
        return fresnel.schlick1(std.math.min(n_dot_wi, n_dot_wo), f0);
    }

    fn volumetricEvaluate(self: *const Sample, wi: Vec4f) bxdf.Result {
        const quo_ior = self.ior;
        if (quo_ior.eta_i == quo_ior.eta_t) {
            return bxdf.Result.empty();
        }

        const wo = self.super.wo;
        const alpha = self.super.alpha;
        const frame = self.super.frame;

        if (!self.super.sameHemisphere(wo)) {
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
            const n_dot_h = math.saturate(frame.nDot(h));

            const schlick = fresnel.Schlick1.init(self.f0[0]);

            const gg = ggx.Iso.refraction(
                n_dot_wi,
                n_dot_wo,
                wi_dot_h,
                wo_dot_h,
                n_dot_h,
                alpha[0],
                ior,
                schlick,
            );

            const comp = ggx.ilmEpDielectric(n_dot_wo, alpha[0], quo_ior.eta_t);

            return bxdf.Result.init(
                @splat(4, std.math.min(n_dot_wi, n_dot_wo) * comp) * gg.reflection,
                gg.pdf(),
            );
        }

        const h = math.normalize3(wo + wi);
        const wo_dot_h = hlp.clampDot(wo, h);
        const n_dot_wi = frame.clampNdot(wi);
        const n_dot_wo = frame.clampAbsNdot(wo);

        if (self.super.avoidCaustics() and alpha[1] <= ggx.Min_alpha) {
            return bxdf.Result.empty();
        }

        const schlick = fresnel.Schlick.init(self.f0);

        var fresnel_result: Vec4f = undefined;
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
            &fresnel_result,
        );

        const mms = ggx.dspbrMicroEc(self.f0, n_dot_wi, n_dot_wo, alpha[1]);
        const base_reflection = @splat(4, n_dot_wi) * (gg.reflection + mms);
        const base_pdf = fresnel_result[0] * gg.pdf();

        if (self.coating.thickness > 0.0) {
            const coating = self.coating.evaluate(wi, wo, h, wo_dot_h, self.super.avoidCaustics());
            const pdf = coating.f * coating.pdf + (1.0 - coating.f) * base_pdf;
            return bxdf.Result.init(coating.reflection + coating.attenuation * base_reflection, pdf);
        }

        return bxdf.Result.init(base_reflection, base_pdf);
    }

    fn volumetricSample(self: Sample, sampler: *Sampler, result: *bxdf.Sample) void {
        if (self.coating.thickness > 0.0) {
            self.coatedVolumetricSample(sampler, result);
            return;
        }

        const wo = self.super.wo;
        const quo_ior = self.ior;
        if (quo_ior.eta_i == quo_ior.eta_t) {
            result.reflection = @splat(4, @as(f32, 1.0));
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

        var n_dot_h: f32 = undefined;
        const h = ggx.Aniso.sample(wo, alpha, xi, frame, &n_dot_h);

        const n_dot_wo = frame.clampAbsNdot(wo);
        const wo_dot_h = hlp.clampDot(wo, h);
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

        const p = s3[0];
        if (same_side) {
            if (p <= f) {
                const n_dot_wi = ggx.Aniso.reflectNoFresnel(
                    wo,
                    h,
                    n_dot_wo,
                    n_dot_h,
                    wi_dot_h,
                    wo_dot_h,
                    alpha,
                    frame,
                    result,
                );

                const mms = ggx.dspbrMicroEc(self.f0, n_dot_wi, n_dot_wo, alpha[1]);
                const reflection = @splat(4, n_dot_wi) * (@splat(4, f) * result.reflection + mms);

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
                result.reflection *= @splat(4, omf * n_dot_wi);
                result.pdf *= omf;
            }
        } else {
            if (p <= f) {
                const n_dot_wi = ggx.Aniso.reflectNoFresnel(
                    wo,
                    h,
                    n_dot_wo,
                    n_dot_h,
                    wi_dot_h,
                    wo_dot_h,
                    alpha,
                    frame,
                    result,
                );

                result.reflection *= @splat(4, f * n_dot_wi);
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
                result.reflection *= @splat(4, omf * n_dot_wi);
                result.pdf *= omf;
            }

            result.reflection *= @splat(4, ggx.ilmEpDielectric(n_dot_wo, alpha[1], quo_ior.eta_t));
        }
    }

    fn coatedVolumetricSample(self: Sample, sampler: *Sampler, result: *bxdf.Sample) void {
        const wo = self.super.wo;
        const quo_ior = self.ior;
        if (quo_ior.eta_i == quo_ior.eta_t) {
            result.reflection = @splat(4, @as(f32, 1.0));
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
        const p = s3[0];

        if (same_side) {
            var coat_n_dot_h: f32 = undefined;
            const cf = self.coating.sample(self.super.wo, xi, &coat_n_dot_h, result);

            if (p <= cf) {
                self.coatingReflect(cf, coat_n_dot_h, result);
            } else {
                var n_dot_h: f32 = undefined;
                const h = ggx.Aniso.sample(wo, alpha, sampler.sample2D(), frame, &n_dot_h);

                const n_dot_wo = frame.clampAbsNdot(wo);
                const wo_dot_h = hlp.clampDot(wo, h);
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
                        wi_dot_h,
                        wo_dot_h,
                        alpha,
                        frame,
                        result,
                    );

                    const mms = ggx.dspbrMicroEc(self.f0, n_dot_wi, n_dot_wo, alpha[1]);
                    const reflection = @splat(4, n_dot_wi) * (@splat(4, f) * result.reflection + mms);

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
                        alpha[1],
                        ior,
                        frame,
                        result,
                    );

                    const omf = 1.0 - f;

                    const coat_n_dot_wo = self.coating.frame.clampAbsNdot(wo);

                    // Approximating the full coating attenuation at entrance, for the benefit of SSS,
                    // which will ignore the border later.
                    // This will probably cause problems for shapes intersecting such materials.
                    const attenuation = self.coating.attenuation(0.5, coat_n_dot_wo);

                    result.reflection *= @splat(4, omf * n_dot_wi) * attenuation;
                    result.pdf *= omf;
                }

                result.pdf *= 1.0 - cf;
            }
        } else {
            var n_dot_h: f32 = undefined;
            const h = ggx.Aniso.sample(wo, alpha, xi, frame, &n_dot_h);

            const n_dot_wo = frame.clampAbsNdot(wo);
            const wo_dot_h = hlp.clampDot(wo, h);
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
                    wi_dot_h,
                    wo_dot_h,
                    alpha,
                    frame,
                    result,
                );

                result.reflection *= @splat(4, f * n_dot_wi);
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

                const omf = 1.0 - f;

                const coat_n_dot_wo = self.coating.frame.clampAbsNdot(wo);
                const attenuation = self.coating.singleAttenuation(coat_n_dot_wo);

                result.reflection *= @splat(4, omf * n_dot_wi) * attenuation;
                result.pdf *= omf;
            }

            result.reflection *= @splat(4, ggx.ilmEpDielectric(n_dot_wo, alpha[1], quo_ior.eta_t));
        }
    }
};
