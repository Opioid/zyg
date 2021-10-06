const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Event = enum { Absorb, Scatter, Pass, Abort };

pub const Result = struct {
    li: Vec4f,
    tr: Vec4f,
    event: Event,
};
