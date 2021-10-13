const Base = @import("../sample_base.zig").SampleBase;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Sample = struct {
    super: Base,

    pub fn init(rs: Renderstate, wo: Vec4f, radiance: Vec4f) Sample {
        return .{ .super = Base.init(
            rs,
            wo,
            radiance,
            radiance,
            @splat(2, @as(f32, 1.0)),
        ) };
    }

    pub fn sample() bxdf.Sample {
        return .{};
    }
};
