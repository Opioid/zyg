const Base = @import("../sample_base.zig").SampleBase;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const base = @import("base");
usingnamespace base.math;
const RNG = base.rnd.Generator;

pub const Sample = struct {
    super: Base,

    pub fn init(rs: Renderstate, wo: Vec4f, albedo: Vec4f) Sample {
        return .{ .super = Base.init(rs, wo, albedo, Vec4f.init1(0.0)) };
    }

    pub fn sample(self: Sample, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        const s2d = sampler.sample2D(rng, 0);

        const is = sampleHemisphereCosine(s2d);
        const wi = self.super.layer.tangentToWorld(is).normalize3();

        const n_dot_wi = self.super.layer.clampNdot(wi);

        const pdf = n_dot_wi * pi_inv;

        const reflection = self.super.albedo.mulScalar3(pdf);

        return .{ .reflection = reflection, .wi = wi, .pdf = pdf };
    }
};
