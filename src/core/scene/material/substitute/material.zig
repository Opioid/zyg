const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Material = struct {
    pub fn sample(self: Material, rs: Renderstate, wo: Vec4f) Sample {
        _ = self;
        return Sample.init(rs, wo, Vec4f.init1(1.0), Vec4f.init1(0.0));
    }
};
