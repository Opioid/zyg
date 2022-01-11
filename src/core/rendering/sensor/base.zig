const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;

pub const Base = struct {
    dimensions: Vec2i = @splat(2, @as(i32, 0)),

    pub const Result = struct {
        last: Vec4f,
        mean: Vec4f,
    };
};
