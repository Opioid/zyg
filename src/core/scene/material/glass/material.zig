const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Material = struct {
    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate) Sample {
        _ = self;
        return Sample.init(rs, wo);
    }
};
