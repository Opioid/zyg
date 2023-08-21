const std = @import("std");
const math = @import("minmax.zig");

pub const Vec2b = @Vector(2, u8);
pub const Vec2i = @Vector(2, i32);
pub const Vec2u = @Vector(2, u32);
pub const Vec2f = @Vector(2, f32);
pub const Vec2ul = @Vector(2, u64);

pub inline fn dot2(a: Vec2f, b: Vec2f) f32 {
    return a[0] * b[0] + a[1] * b[1];
}

pub inline fn squaredLength2(v: Vec2f) f32 {
    return dot2(v, v);
}

pub inline fn length2(v: Vec2f) f32 {
    return @sqrt(dot2(v, v));
}

pub inline fn normalize2(v: Vec2f) Vec2f {
    const i = @sqrt(1.0 / dot2(v, v));
    return @as(Vec2f, @splat(i)) * v;
}

pub inline fn min2(a: Vec2f, b: Vec2f) Vec2f {
    return .{ math.min(a[0], b[0]), math.min(a[1], b[1]) };
}

pub inline fn max2(a: Vec2f, b: Vec2f) Vec2f {
    return .{ math.max(a[0], b[0]), math.max(a[1], b[1]) };
}

pub inline fn vec2fTo2i(v: Vec2f) Vec2i {
    return .{ @intFromFloat(v[0]), @intFromFloat(v[1]) };
}

pub inline fn vec2fTo2u(v: Vec2f) Vec2u {
    return .{ @intFromFloat(v[0]), @intFromFloat(v[1]) };
}

pub inline fn vec2iTo2f(v: Vec2i) Vec2f {
    return .{ @floatFromInt(v[0]), @floatFromInt(v[1]) };
}

pub inline fn vec2uTo2f(v: Vec2u) Vec2f {
    return .{ @floatFromInt(v[0]), @floatFromInt(v[1]) };
}
