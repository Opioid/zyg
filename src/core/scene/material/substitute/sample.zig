const Base = @import("../sample_base.zig").SampleBase;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

pub const Sample = struct {
    super: Base,

    pub fn init(rs: Renderstate, wo: Vec4f, albedo: Vec4f, radiance: Vec4f) Sample {
        return .{ .super = Base.init(rs, wo, albedo, radiance) };
    }

    pub fn sample(self: Sample, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        const s2d = sampler.sample2D(rng, 0);

        const is = math.smpl.hemisphereCosine(s2d);
        const wi = self.super.layer.tangentToWorld(is).normalize3();

        const n_dot_wi = self.super.layer.clampNdot(wi);

        const pdf = n_dot_wi * math.pi_inv;

        const reflection = self.super.albedo.mulScalar3(pdf);

        return .{ .reflection = reflection, .wi = wi, .pdf = pdf };
    }
};
