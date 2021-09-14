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

    pub fn init(rs: Renderstate, wo: Vec4f) Sample {
        return .{ .super = Base.init(rs, wo, @splat(4, @as(f32, 1.0)), @splat(4, @as(f32, 0.0))) };
    }

    pub fn sample(self: Sample, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        _ = self;
        _ = sampler;
        _ = rng;
        return .{ .reflection = undefined, .wi = undefined, .pdf = 0.0 };
    }
};
