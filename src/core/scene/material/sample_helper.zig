const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Dot_min: f32 = 0.00001;

pub fn absDotC(a: Vec4f, b: Vec4f, c: bool) f32 {
    const d = math.dot3(a, b);
    return if (c) @fabs(d) else d;
}

pub fn clamp(x: f32) f32 {
    return std.math.clamp(x, Dot_min, 1.0);
}

pub fn clampAbs(x: f32) f32 {
    return std.math.clamp(@fabs(x), Dot_min, 1.0);
}

pub fn clampDot(a: Vec4f, b: Vec4f) f32 {
    return std.math.clamp(math.dot3(a, b), Dot_min, 1.0);
}

pub fn clampAbsDot(a: Vec4f, b: Vec4f) f32 {
    return std.math.clamp(@fabs(math.dot3(a, b)), Dot_min, 1.0);
}
