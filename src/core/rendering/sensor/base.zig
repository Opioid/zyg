const math = @import("base").math;
const Vec2i = math.Vec2i;

pub const Base = struct {
    dimensions: Vec2i = Vec2i.init1(0),
};
