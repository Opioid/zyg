const base = @import("base");
usingnamespace base.math;

const std = @import("std");

pub const Dot_min: f32 = 0.00001;

pub fn clampDot(a: Vec4f, b: Vec4f) f32 {
    return std.math.clamp(a.dot3(b), 0.0, Dot_min);
}