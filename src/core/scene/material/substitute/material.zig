const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Material = struct {
    color: Vec4f = undefined,

    pub fn sample(self: Material, rs: Renderstate, wo: Vec4f) Sample {
        return Sample.init(rs, wo, self.color, Vec4f.init1(0.0));
    }
};
