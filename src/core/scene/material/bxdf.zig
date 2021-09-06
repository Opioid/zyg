const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Sample = struct {
    reflection: Vec4f,
    wi: Vec4f,
    pdf: f32,
};
