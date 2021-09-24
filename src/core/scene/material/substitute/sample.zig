const Base = @import("../sample_base.zig").SampleBase;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const disney = @import("../disney.zig");
const fresnel = @import("../fresnel.zig");
const ggx = @import("../ggx.zig");
const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

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

    pub fn sample(self: Sample, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        // const s2d = sampler.sample2D(rng, 0);

        // const is = math.smpl.hemisphereCosine(s2d);
        // const wi = math.normalize3(self.super.layer.tangentToWorld(is));

        // const n_dot_wi = self.super.layer.clampNdot(wi);

        // const pdf = n_dot_wi * math.pi_inv;

        // const reflection = @splat(4, pdf) * self.super.albedo;

        // return .{ .reflection = reflection, .wi = wi, .pdf = pdf };

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

    fn diffuseSample(self: Sample, sampler: *Sampler, rng: *RNG, result: *bxdf.Sample) void {
        const n_dot_wo = self.super.layer.clampAbsNdot(self.super.wo);

        const xi = sampler.sample2D(rng, 0);

        const n_dot_wi = disney.Iso.reflect(
            self.super.wo,
            n_dot_wo,
            self.super.layer,
            self.super.alpha[0],
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
            self.super.alpha,
            schlick,
            self.super.layer,
        );

        gg.reflection *= ggx.ilmEpConductor(self.f0, n_dot_wo, self.super.alpha[0], self.metallic);

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
