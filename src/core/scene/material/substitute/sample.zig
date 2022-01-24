const sample = @import("../sample_base.zig");
const Base = sample.SampleBase;
const IoR = sample.IoR;
const Coating = @import("coating.zig").Coating;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const ccoef = @import("../collision_coefficients.zig");
const disney = @import("../disney.zig");
const lambert = @import("../lambert.zig");
const fresnel = @import("../fresnel.zig");
const hlp = @import("../sample_helper.zig");
const inthlp = @import("../../../rendering/integrator/helper.zig");
const ggx = @import("../ggx.zig");

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");

pub const Sample = struct {
    super: Base,

    coating: Coating = undefined,

    f0: Vec4f,
    translucent_color: Vec4f = undefined,
    attenuation: Vec4f = undefined,

    ior: IoR,

    metallic: f32,
    thickness: f32 = 0.0,
    transparency: f32 = undefined,

    volumetric: bool,

    pub fn init(
        rs: Renderstate,
        wo: Vec4f,
        albedo: Vec4f,
        radiance: Vec4f,
        alpha: Vec2f,
        ior: f32,
        ior_outside: f32,
        metallic: f32,
        volumetric: bool,
    ) Sample {
        const color = @splat(4, 1.0 - metallic) * albedo;

        var super = Base.init(rs, wo, color, radiance, alpha);
        super.properties.set(.CanEvaluate, ior != ior_outside);

        const f0 = fresnel.Schlick.F0(ior, ior_outside);

        return .{
            .super = super,
            .f0 = math.lerp3(@splat(4, f0), albedo, metallic),
            .metallic = metallic,
            .ior = .{ .eta_t = ior, .eta_i = ior_outside },
            .volumetric = volumetric,
        };
    }

    pub fn setTranslucency(
        self: *Sample,
        color: Vec4f,
        thickness: f32,
        attenuation_distance: f32,
        transparency: f32,
    ) void {
        self.super.properties.set(.Translucent, true);
        self.super.albedo = @splat(4, 1.0 - transparency) * color;
        self.translucent_color = color;
        self.attenuation = ccoef.attenuationCoefficient(color, attenuation_distance);
        self.thickness = thickness;
        self.transparency = transparency;
        self.volumetric = false;
    }

    pub fn evaluate(self: Sample, wi: Vec4f) bxdf.Result {
        if (self.volumetric) {
            return self.volumetricEvaluate(wi);
        }

        const wo = self.super.wo;

        const tr = self.transparency;
        const th = self.thickness;
        const translucent = th > 0.0;

        if (translucent) {
            if (!self.super.sameHemisphere(wi)) {
                const n_dot_wi = self.super.layer.clampAbsNdot(wi);
                const n_dot_wo = self.super.layer.clampAbsNdot(wo);

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

    pub fn sample(self: Sample, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        var result = bxdf.Sample{ .wavelength = 0.0 };

        const th = self.thickness;
        if (th > 0.0) {
            const tr = self.transparency;

            const p = sampler.sample1D(rng, 0);
            if (p < tr) {
                const n_dot_wi = lambert.reflect(self.translucent_color, self.super.layer, sampler, rng, &result);
                const n_dot_wo = self.super.layer.clampAbsNdot(self.super.wo);

                const f = diffuseFresnelHack(n_dot_wi, n_dot_wo, self.f0[0]);

                const approx_dist = th / n_dot_wi;
                const attenuation = inthlp.attenuation3(self.attenuation, approx_dist);

                result.wi = -result.wi;
                result.reflection *= @splat(4, tr * n_dot_wi * (1.0 - f)) * attenuation;
                result.pdf *= tr;
            } else {
                const o = 1.0 - tr;

                if (p < tr + 0.5 * o) {
                    self.diffuseSample(sampler, rng, &result);
                } else {
                    self.glossSample(sampler, rng, &result);
                }

                result.pdf *= o;
            }
        } else {
            if (self.volumetric) {
                self.volumetricSample(sampler, rng, &result);
                return result;
            }

            if (!self.super.sameHemisphere(self.super.wo)) {
                return result;
            }

            if (self.coating.thickness > 0.0) {
                self.coatingSample(sampler, rng, &result);
            } else {
                self.baseSample(sampler, rng, &result);
            }
        }

        return result;
    }

    fn baseEvaluate(self: Sample, wi: Vec4f, wo: Vec4f, h: Vec4f, wo_dot_h: f32) bxdf.Result {
        const alpha = self.super.alpha;

        const n_dot_wi = self.super.layer.clampNdot(wi);
        const n_dot_wo = self.super.layer.clampAbsNdot(wo);

        const d = disney.Iso.reflection(wo_dot_h, n_dot_wi, n_dot_wo, alpha[0], self.super.albedo);

        if (self.super.avoidCaustics() and alpha[0] <= ggx.Min_alpha) {
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
            self.super.layer,
        );

        gg.reflection *= ggx.ilmEpConductor(self.f0, n_dot_wo, alpha[0], self.metallic);

        const pdf = 0.5 * (d.pdf() + gg.pdf());

        return bxdf.Result.init(@splat(4, n_dot_wi) * (d.reflection + gg.reflection), pdf);
    }

    fn pureGlossEvaluate(self: Sample, wi: Vec4f, wo: Vec4f, h: Vec4f, wo_dot_h: f32) bxdf.Result {
        const alpha = self.super.alpha;

        if (self.super.avoidCaustics() and alpha[0] <= ggx.Min_alpha) {
            return bxdf.Result.empty();
        }

        const n_dot_wi = self.super.layer.clampNdot(wi);
        const n_dot_wo = self.super.layer.clampAbsNdot(wo);

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
            self.super.layer,
        );

        gg.reflection *= ggx.ilmEpConductor(self.f0, n_dot_wo, alpha[0], self.metallic);

        return bxdf.Result.init(@splat(4, n_dot_wi) * gg.reflection, gg.pdf());
    }

    fn baseSample(self: Sample, sampler: *Sampler, rng: *RNG, result: *bxdf.Sample) void {
        if (1.0 == self.metallic) {
            self.pureGlossSample(sampler, rng, result);
        } else {
            const p = sampler.sample1D(rng, 0);
            if (p < 0.5) {
                self.diffuseSample(sampler, rng, result);
            } else {
                self.glossSample(sampler, rng, result);
            }
        }
    }

    fn coatingSample(self: Sample, sampler: *Sampler, rng: *RNG, result: *bxdf.Sample) void {
        var n_dot_h: f32 = undefined;
        const f = self.coating.sample(self.super.wo, sampler, rng, &n_dot_h, result);

        const p = sampler.sample1D(rng, 0);
        if (p <= f) {
            self.coatingReflect(f, n_dot_h, result);
        } else {
            if (1.0 == self.metallic) {
                self.coatingBaseSample(pureGlossSample, sampler, rng, f, result);
            } else {
                const p1 = (p - f) / (1.0 - f);
                if (p1 < 0.5) {
                    self.coatingBaseSample(diffuseSample, sampler, rng, f, result);
                } else {
                    self.coatingBaseSample(glossSample, sampler, rng, f, result);
                }
            }
        }
    }

    fn diffuseSample(self: Sample, sampler: *Sampler, rng: *RNG, result: *bxdf.Sample) void {
        const wo = self.super.wo;
        const alpha = self.super.alpha;

        const n_dot_wo = self.super.layer.clampAbsNdot(wo);

        const xi = sampler.sample2D(rng, 0);

        const n_dot_wi = disney.Iso.reflect(
            wo,
            n_dot_wo,
            self.super.layer,
            alpha[0],
            self.super.albedo,
            xi,
            result,
        );

        if (self.super.avoidCaustics() and alpha[0] <= ggx.Min_alpha) {
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
            self.super.layer,
        );

        gg.reflection *= ggx.ilmEpConductor(self.f0, n_dot_wo, alpha[0], self.metallic);

        result.reflection = @splat(4, n_dot_wi) * (result.reflection + gg.reflection);
        result.pdf = 0.5 * (result.pdf + gg.pdf());
    }

    fn glossSample(self: Sample, sampler: *Sampler, rng: *RNG, result: *bxdf.Sample) void {
        const wo = self.super.wo;
        const alpha = self.super.alpha;

        const n_dot_wo = self.super.layer.clampAbsNdot(wo);

        const schlick = fresnel.Schlick.init(self.f0);

        const xi = sampler.sample2D(rng, 0);

        const n_dot_wi = ggx.Aniso.reflect(
            wo,
            n_dot_wo,
            alpha,
            xi,
            schlick,
            self.super.layer,
            result,
        );

        result.reflection *= ggx.ilmEpConductor(self.f0, n_dot_wo, alpha[0], self.metallic);

        const d = disney.Iso.reflection(
            result.h_dot_wi,
            n_dot_wi,
            n_dot_wo,
            alpha[0],
            self.super.albedo,
        );

        result.reflection = @splat(4, n_dot_wi) * (result.reflection + d.reflection);
        result.pdf = 0.5 * (result.pdf + d.pdf());
    }

    fn pureGlossSample(self: Sample, sampler: *Sampler, rng: *RNG, result: *bxdf.Sample) void {
        const wo = self.super.wo;
        const alpha = self.super.alpha;

        const n_dot_wo = self.super.layer.clampAbsNdot(wo);

        const schlick = fresnel.Schlick.init(self.f0);

        const xi = sampler.sample2D(rng, 0);

        const n_dot_wi = ggx.Aniso.reflect(
            wo,
            n_dot_wo,
            alpha,
            xi,
            schlick,
            self.super.layer,
            result,
        );

        result.reflection *= @splat(4, n_dot_wi) *
            ggx.ilmEpConductor(self.f0, n_dot_wo, alpha[0], self.metallic);
    }

    fn coatingReflect(self: Sample, f: f32, n_dot_h: f32, result: *bxdf.Sample) void {
        const wo = self.super.wo;
        const n_dot_wo = self.coating.layer.clampAbsNdot(self.super.wo);

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

        const base_result = if (1.0 == self.metallic)
            self.pureGlossEvaluate(result.wi, wo, result.h, result.h_dot_wi)
        else
            self.baseEvaluate(result.wi, wo, result.h, result.h_dot_wi);

        result.reflection = result.reflection + coating_attenuation * base_result.reflection;
        result.pdf = f * result.pdf + (1.0 - f) * base_result.pdf();
    }

    const SampleFunc = fn (self: Sample, sampler: *Sampler, rng: *RNG, result: *bxdf.Sample) void;

    fn coatingBaseSample(
        self: Sample,
        sampleFunc: SampleFunc,
        sampler: *Sampler,
        rng: *RNG,
        f: f32,
        result: *bxdf.Sample,
    ) void {
        sampleFunc(self, sampler, rng, result);

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

    fn volumetricEvaluate(self: Sample, wi: Vec4f) bxdf.Result {
        const quo_ior = self.ior;
        if (quo_ior.eta_i == quo_ior.eta_t) {
            return bxdf.Result.empty();
        }

        const wo = self.super.wo;
        const alpha = self.super.alpha[0];
        const layer = self.super.layer;

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

            const n_dot_wi = layer.clampNdot(wi);
            const n_dot_wo = layer.clampAbsNdot(wo);
            const n_dot_h = math.saturate(layer.nDot(h));

            const schlick = fresnel.Schlick1.init(self.f0[0]);

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

            const comp = ggx.ilmEpDielectric(n_dot_wo, alpha, quo_ior.eta_t);

            return bxdf.Result.init(
                @splat(4, std.math.min(n_dot_wi, n_dot_wo) * comp) * gg.reflection,
                gg.pdf(),
            );
        }

        const h = math.normalize3(wo + wi);
        const wo_dot_h = hlp.clampDot(wo, h);

        if (1.0 == self.metallic) {
            return self.pureGlossEvaluate(wi, wo, h, wo_dot_h);
        }

        const n_dot_wi = layer.clampNdot(wi);
        const n_dot_wo = layer.clampAbsNdot(wo);

        const d = disney.IsoNoLambert.reflection(wo_dot_h, n_dot_wi, n_dot_wo, alpha, self.super.albedo);

        if (self.super.avoidCaustics() and alpha <= ggx.Min_alpha) {
            return bxdf.Result.init(@splat(4, n_dot_wi) * d.reflection, d.pdf());
        }

        const n_dot_h = math.saturate(layer.nDot(h));
        const schlick = fresnel.Schlick.init(self.f0);

        var fresnel_result: Vec4f = undefined;
        var gg = ggx.Iso.reflectionF(
            n_dot_wi,
            n_dot_wo,
            wo_dot_h,
            n_dot_h,
            alpha,
            schlick,
            &fresnel_result,
        );

        gg.reflection *= ggx.ilmEpConductor(self.f0, n_dot_wo, alpha, self.metallic);

        const pdf = fresnel_result[0] * gg.pdf();

        return bxdf.Result.init(@splat(4, n_dot_wi) * (d.reflection + gg.reflection), pdf);
    }

    fn volumetricSample(self: Sample, sampler: *Sampler, rng: *RNG, result: *bxdf.Sample) void {
        const wo = self.super.wo;
        const quo_ior = self.ior;
        if (quo_ior.eta_i == quo_ior.eta_t) {
            result.reflection = @splat(4, @as(f32, 1.0));
            result.wi = -wo;
            result.pdf = 1.0;
            result.typef.clearWith(.SpecularTransmission);
            return;
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

        const p = sampler.sample1D(rng, 0);
        if (same_side) {
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
                    result,
                );

                const d = disney.IsoNoLambert.reflection(
                    result.h_dot_wi,
                    n_dot_wi,
                    n_dot_wo,
                    alpha[0],
                    self.super.albedo,
                );

                const reflection = @splat(4, n_dot_wi) * (@splat(4, f) * result.reflection + d.reflection);

                result.reflection = reflection * ggx.ilmEpConductor(
                    self.f0,
                    n_dot_wo,
                    alpha[0],
                    self.metallic,
                );
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
                    layer,
                    result,
                );

                const omf = 1.0 - f;
                result.reflection *= @splat(4, omf * n_dot_wi);
                result.pdf *= omf;
            }
        } else {
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
                    layer,
                    result,
                );

                const omf = 1.0 - f;
                result.reflection *= @splat(4, omf * n_dot_wi);
                result.pdf *= omf;
            }

            result.reflection *= @splat(4, ggx.ilmEpDielectric(n_dot_wo, alpha[0], quo_ior.eta_t));
        }
    }
};
