const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;

pub const CameraSample = struct {
    pixel: Vec2i,
    pixel_uv: Vec2f,
};
