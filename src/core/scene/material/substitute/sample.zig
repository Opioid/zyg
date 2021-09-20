const Base = @import("../sample_base.zig").SampleBase;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const disney = @import("../disney.zig");
const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

pub const Sample = struct {
    super: Base,

    metallic: f32,

    pub fn init(
        rs: Renderstate,
        wo: Vec4f,
        albedo: Vec4f,
        radiance: Vec4f,
        alpha: Vec2f,
        metallic: f32,
    ) Sample {
        return .{
            .super = Base.init(rs, wo, albedo, radiance, alpha),
            .metallic = metallic,
        };
    }

    pub fn initN(
        rs: Renderstate,
        shading_n: Vec4f,
        wo: Vec4f,
        albedo: Vec4f,
        radiance: Vec4f,
        alpha: Vec2f,
        metallic: f32,
    ) Sample {
        return .{
            .super = Base.initN(rs, shading_n, wo, albedo, radiance, alpha),
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
        self.diffuseSample(sampler, rng, &result);
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

        result.reflection = @splat(4, n_dot_wi) * result.reflection;
    }
};
