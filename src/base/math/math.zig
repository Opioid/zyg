pub const aabb = @import("aabb.zig");
pub const AABB = aabb.AABB;
pub usingnamespace @import("interpolated_function.zig");
pub const quaternion = @import("quaternion.zig");
pub const Quaternion = quaternion.Quaternion;
pub usingnamespace @import("matrix3x3.zig");
pub usingnamespace @import("matrix4x4.zig");
pub usingnamespace @import("ray.zig");
pub usingnamespace @import("sample_distribution.zig");
pub const smpl = @import("sampling.zig");
pub usingnamespace @import("transformation.zig");
pub usingnamespace @import("vector2.zig");
pub usingnamespace @import("vector3.zig");
pub usingnamespace @import("vector4.zig");

const std = @import("std");

pub const pi_inv = 1.0 / std.math.pi;

pub fn degreesToRadians(degrees: anytype) @TypeOf(degrees) {
    return degrees * (std.math.pi / 180.0);
}

pub fn lerp(a: f32, b: f32, t: f32) f32 {
    const u = 1.0 - t;
    return u * a + t * b;
}

pub fn frac(x: f32) f32 {
    return x - std.math.floor(x);
}

pub fn pow5(x: f32) f32 {
    const x2 = x * x;
    const x4 = x2 * x2;
    return x4 * x;
}
