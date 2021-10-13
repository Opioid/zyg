const std = @import("std");

pub const Vec2b = std.meta.Vector(2, u8);
pub const Vec2i = std.meta.Vector(2, i32);
pub const Vec2f = std.meta.Vector(2, f32);

pub fn dot2(a: Vec2f, b: Vec2f) f32 {
    return a[0] * b[0] + a[1] * b[1];
}

pub fn vec2fTo2i(v: Vec2f) Vec2i {
    return .{ @floatToInt(i32, v[0]), @floatToInt(i32, v[1]) };
}

pub fn vec2iTo2f(v: Vec2i) Vec2f {
    return .{ @intToFloat(f32, v[0]), @intToFloat(f32, v[1]) };
}
