const math = @import("vector4.zig");
const Vec4f = math.Vec4f;

pub fn createPN(normal: Vec4f, point: Vec4f) Vec4f {
    return .{ normal[0], normal[1], normal[2], -math.dot3(normal, point) };
}

pub fn dot(p: Vec4f, v: Vec4f) f32 {
    return (p[0] * v[0] + p[1] * v[1]) + (p[2] * v[2] + p[3]);
}
