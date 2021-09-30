const Base = @import("../sample_base.zig").SampleBase;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const disney = @import("../disney.zig");
const fresnel = @import("../fresnel.zig");
const hlp = @import("../sample_helper.zig");
const ggx = @import("../ggx.zig");
const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");

pub const Sample = struct {
    super: Base,

    albedo: Vec4f,
    f0: Vec4f,

    metallic: f32,

    pub fn init(
        rs: Renderstate,
        wo: Vec4f,
        albedo: Vec4f,
        radiance: Vec4f,
        alpha: Vec2f,
        f0: f32,
        metallic: f32,
    ) Sample {
        return .{
            .super = Base.init(rs, wo, albedo, radiance, alpha),
            .albedo = @splat(4, 1.0 - metallic) * albedo,
            .f0 = math.lerp3(@splat(4, f0), albedo, metallic),
            .metallic = metallic,
        };
    }

    pub fn evaluate(self: Sample, wi: Vec4f) bxdf.Result {
        const wo = self.super.wo;

        // if (!self.super.sameHemisphere(wo)) {
        //     return bxdf.Result.init(@splat(4, @as(f32, 0.0)), 0.0);
        // }

        const h = math.normalize3(wo + wi);

        const wo_dot_h = hlp.clampDot(wo, h);

        if (1.0 == self.metallic) {
            return self.pureGlossEvaluate(wi, wo, h, wo_dot_h);
        }

        return self.baseEvaluate(wi, wo, h, wo_dot_h);
    }

    pub fn sample(self: Sample, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        var result = bxdf.Sample{};

        if (1.0 == self.metallic) {
            self.pureGlossSample(sampler, rng, &result);
        } else {
            const p = sampler.sample1D(rng, 0);

            if (p < 0.5) {
                self.diffuseSample(sampler, rng, &result);
            } else {
                self.glossSample(sampler, rng, &result);
            }
        }

        return result;
    }

    fn baseEvaluate(self: Sample, wi: Vec4f, wo: Vec4f, h: Vec4f, wo_dot_h: f32) bxdf.Result {
        const alpha = self.super.alpha;

        const n_dot_wi = self.super.layer.clampNdot(wi);
        const n_dot_wo = self.super.layer.clampAbsNdot(wo);

        const d = disney.Iso.reflection(wo_dot_h, n_dot_wi, n_dot_wo, alpha[0], self.albedo);

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

    fn diffuseSample(self: Sample, sampler: *Sampler, rng: *RNG, result: *bxdf.Sample) void {
        const alpha = self.super.alpha;

        const n_dot_wo = self.super.layer.clampAbsNdot(self.super.wo);

        const xi = sampler.sample2D(rng, 0);

        const n_dot_wi = disney.Iso.reflect(
            self.super.wo,
            n_dot_wo,
            self.super.layer,
            alpha[0],
            self.super.albedo,
            xi,
            result,
        );

        const schlick = fresnel.Schlick.init(self.f0);

        var gg = ggx.Aniso.reflection(
            result.wi,
            self.super.wo,
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
        const n_dot_wo = self.super.layer.clampAbsNdot(self.super.wo);

        const schlick = fresnel.Schlick.init(self.f0);

        const xi = sampler.sample2D(rng, 0);

        const n_dot_wi = ggx.Aniso.reflect(
            self.super.wo,
            n_dot_wo,
            self.super.alpha,
            xi,
            schlick,
            self.super.layer,
            result,
        );

        result.reflection *= ggx.ilmEpConductor(self.f0, n_dot_wo, self.super.alpha[0], self.metallic);

        const d = disney.Iso.reflection(
            result.h_dot_wi,
            n_dot_wi,
            n_dot_wo,
            self.super.alpha[0],
            self.super.albedo,
        );

        result.reflection = @splat(4, n_dot_wi) * (result.reflection + d.reflection);
        result.pdf = 0.5 * (result.pdf + d.pdf());
    }

    fn pureGlossSample(self: Sample, sampler: *Sampler, rng: *RNG, result: *bxdf.Sample) void {
        const n_dot_wo = self.super.layer.clampAbsNdot(self.super.wo);

        const schlick = fresnel.Schlick.init(self.f0);

        const xi = sampler.sample2D(rng, 0);

        const n_dot_wi = ggx.Aniso.reflect(
            self.super.wo,
            n_dot_wo,
            self.super.alpha,
            xi,
            schlick,
            self.super.layer,
            result,
        );

        result.reflection *= @splat(4, n_dot_wi) *
            ggx.ilmEpConductor(self.f0, n_dot_wo, self.super.alpha[0], self.metallic);
    }
};
