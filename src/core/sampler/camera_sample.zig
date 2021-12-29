const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const CameraSample = struct {
    pixel: Vec2i,
    pixel_uv: Vec2f,
    lens_uv: Vec2f,
    time: f32,
    weight: f32,
};

pub const CameraSampleTo = struct {
    pixel: Vec2i,
    pixel_uv: Vec2f,
    dir: Vec4f,
    t: f32,
    pdf: f32,
};
