const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Event = enum { Absorb, Scatter, Pass, Abort };

pub const Result = struct {
    li: Vec4f,
    tr: Vec4f,
    t: f32 = undefined,
    event: Event,

    pub fn initPass(w: Vec4f) Result {
        return .{
            .li = @splat(4, @as(f32, 0.0)),
            .tr = w,
            .event = .Pass,
        };
    }
};
