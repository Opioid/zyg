pub const interpolated_function = @import("interpolated_function.zig");
pub usingnamespace interpolated_function;
pub const quaternion = @import("quaternion.zig");
pub const Quaternion = quaternion.Quaternion;
pub usingnamespace @import("matrix3x3.zig");
pub usingnamespace @import("matrix4x4.zig");
pub usingnamespace @import("ray.zig");
pub usingnamespace @import("sample_distribution.zig");
pub const sample = @import("sample.zig");
pub usingnamespace @import("transformation.zig");
pub usingnamespace @import("vector2.zig");
pub usingnamespace @import("vector3.zig");
pub usingnamespace @import("vector4.zig");

const std = @import("std");

pub fn degreesToRadians(degrees: anytype) @TypeOf(degrees) {
    return degrees * std.math.pi / 180.0;
}

pub fn lerp(a: f32, b: f32, t: f32) f32 {
    const u = 1.0 - t;
    return u * a + t * b;
}
