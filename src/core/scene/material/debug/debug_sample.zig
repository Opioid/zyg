const Base = @import("../sample_base.zig").Base;
const bxdf = @import("../bxdf.zig");
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub const Sample = struct {
    super: Base,

    pub fn init(rs: Renderstate, wo: Vec4f, albedo: Vec4f) Sample {
        return .{ .super = Base.initTBN(rs, wo, albedo, @splat(1.0), 0.0, true) };
    }

    pub fn evaluate(self: *const Sample, wi: Vec4f) bxdf.Result {
        const n_dot_wi = self.super.frame.clampNdot(wi);
        const pdf = n_dot_wi * math.pi_inv;

        const reflection = @as(Vec4f, @splat(pdf)) * self.super.albedo;

        return bxdf.Result.init(reflection, pdf);
    }

    pub fn sample(self: *const Sample, sampler: *Sampler) bxdf.Sample {
        const s2d = sampler.sample2D();

        const is = math.smpl.hemisphereCosine(s2d);
        const wi = math.normalize3(self.super.frame.frameToWorld(is));

        const n_dot_wi = self.super.frame.clampNdot(wi);
        const pdf = n_dot_wi * math.pi_inv;

        const reflection = @as(Vec4f, @splat(pdf)) * self.super.albedo;

        return .{
            .reflection = reflection,
            .wi = wi,
            .pdf = pdf,
            .split_weight = 1.0,
            .wavelength = 0.0,
            .class = .{ .diffuse = true, .reflection = true },
        };
    }
};
