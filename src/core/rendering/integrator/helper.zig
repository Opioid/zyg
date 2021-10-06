const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub fn attenuation3(c: Vec4f, distance: f32) Vec4f {
    return math.exp(@splat(4, -distance) * c);
}
