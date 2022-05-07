pub const aabb = @import("aabb.zig");
pub const AABB = aabb.AABB;
pub const cone = @import("cone.zig");
pub usingnamespace @import("distribution_1d.zig");
pub usingnamespace @import("distribution_2d.zig");
pub usingnamespace @import("distribution_3d.zig");
pub usingnamespace @import("interpolated_function.zig");
pub const quaternion = @import("quaternion.zig");
pub const Quaternion = quaternion.Quaternion;
pub usingnamespace @import("matrix3x3.zig");
pub usingnamespace @import("matrix4x4.zig");
pub usingnamespace @import("ray.zig");
pub usingnamespace @import("sample_distribution.zig");
pub const smpl = @import("sampling.zig");
pub usingnamespace @import("transformation.zig");
const vec2 = @import("vector2.zig");
pub usingnamespace vec2;
pub usingnamespace @import("vector3.zig");
const vec4 = @import("vector4.zig");
pub usingnamespace vec4;
pub const plane = @import("plane.zig");

const std = @import("std");

pub const pi_inv = 1.0 / std.math.pi;

pub fn degreesToRadians(degrees: anytype) @TypeOf(degrees) {
    return degrees * (std.math.pi / 180.0);
}

pub fn radiansToDegrees(radians: anytype) @TypeOf(radians) {
    return radians * (180.0 / std.math.pi);
}

pub fn saturate(x: f32) f32 {
    return std.math.clamp(x, 0.0, 1.0);
}

pub fn lerp(a: f32, b: f32, t: f32) f32 {
    const u = 1.0 - t;
    return u * a + t * b;
}

pub fn lerp2(a: vec2.Vec2f, b: vec2.Vec2f, t: f32) vec2.Vec2f {
    const u = @splat(2, 1.0 - t);
    return u * a + @splat(2, t) * b;
}

pub fn lerp3(a: vec4.Vec4f, b: vec4.Vec4f, t: f32) vec4.Vec4f {
    const u = @splat(4, 1.0 - t);
    return u * a + @splat(4, t) * b;
}

pub fn frac(x: f32) f32 {
    return x - @floor(x);
}

pub fn pow2(x: f32) f32 {
    return x * x;
}

pub fn pow5(x: f32) f32 {
    const x2 = x * x;
    const x4 = x2 * x2;
    return x4 * x;
}

pub fn bilinear1(c: [4]f32, s: f32, t: f32) f32 {
    const _s = 1.0 - s;
    const _t = 1.0 - t;

    return _t * (_s * c[0] + s * c[1]) + t * (_s * c[2] + s * c[3]);
}

pub fn bilinear3(c: [4]vec4.Vec4f, s: f32, t: f32) vec4.Vec4f {
    const vs = @splat(4, s);
    const vt = @splat(4, t);

    const _s = @splat(4, @as(f32, 1.0)) - vs;
    const _t = @splat(4, @as(f32, 1.0)) - vt;

    return _t * (_s * c[0] + vs * c[1]) + vt * (_s * c[2] + vs * c[3]);
}

pub fn roundUp(comptime T: type, x: T, m: T) T {
    return ((x + m - 1) / m) * m;
}
