const Base = @import("../material_base.zig").Base;
const Sample = @import("hair_sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub const Material = struct {
    super: Base = .{},

    color: Vec4f = @splat(0.5),

    pub fn sample(self: *const Material, wo: Vec4f, rs: Renderstate, sampler: *Sampler) Sample {
        _ = sampler;

        var result = Sample.init(rs, wo, self.color);
        result.super.frame.setTangentFrame(rs.t, rs.b, rs.n);
        return result;
    }
};
