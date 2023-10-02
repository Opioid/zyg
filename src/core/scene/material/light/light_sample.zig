const Base = @import("../sample_base.zig").Base;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");

const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Sample = struct {
    super: Base,

    pub fn init(rs: Renderstate, wo: Vec4f) Sample {
        return .{ .super = Base.init(
            rs,
            wo,
            @splat(0.0),
            @splat(1.0),
            0.0,
        ) };
    }

    pub fn sample() bxdf.Sample {
        return .{ .split_weight = 1.0, .wavelength = 0.0 };
    }
};
