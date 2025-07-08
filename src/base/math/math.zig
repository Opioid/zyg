pub const AABB = @import("aabb.zig").AABB;
pub const cone = @import("cone.zig");
pub const Distribution1D = @import("distribution_1d.zig").Distribution1D;
const dist2D = @import("distribution_2d.zig");
pub const Distribution2D = dist2D.Distribution2D;
pub const Distribution2DN = dist2D.Distribution2DN;
pub const Distribution3D = @import("distribution_3d.zig").Distribution3D;
pub const Frame = @import("frame.zig").Frame;
pub const ifunc = @import("interpolated_function.zig");

const minmax = @import("minmax.zig");
pub const min = minmax.min;
pub const max = minmax.max;
pub const clamp = minmax.clamp;

pub const quaternion = @import("quaternion.zig");
pub const Quaternion = quaternion.Quaternion;

const mat3 = @import("matrix3x3.zig");
pub const Mat2x3 = mat3.Mat2x3;
pub const Mat3x3 = mat3.Mat3x3;

pub const Mat4x4 = @import("matrix4x4.zig").Mat4x4;
pub const Ray = @import("ray.zig").Ray;
pub const distr = @import("sample_distribution.zig");
pub const smpl = @import("sampling.zig");
pub const Transformation = @import("transformation.zig").Transformation;

const vec2 = @import("vector2.zig");
pub const Vec2b = vec2.Vec2b;
pub const Vec2i = vec2.Vec2i;
pub const Vec2u = vec2.Vec2u;
pub const Vec2f = vec2.Vec2f;
pub const Vec2ul = vec2.Vec2ul;
pub const dot2 = vec2.dot2;
pub const squaredLength2 = vec2.squaredLength2;
pub const length2 = vec2.length2;
pub const normalize2 = vec2.normalize2;
pub const min2 = vec2.min2;
pub const max2 = vec2.max2;
pub const clamp2 = vec2.clamp2;

const vec3 = @import("vector3.zig");
pub const Pack3b = vec3.Pack3b;
pub const Pack3h = vec3.Pack3h;
pub const Pack3f = vec3.Pack3f;

const vec4 = @import("vector4.zig");
pub const Pack4b = vec4.Pack4b;
pub const Pack4h = vec4.Pack4h;
pub const Pack4i = vec4.Pack4i;
pub const Pack4f = vec4.Pack4f;
pub const Vec4b = vec4.Vec4b;
pub const Vec4us = vec4.Vec4us;
pub const Vec4i = vec4.Vec4i;
pub const Vec4u = vec4.Vec4u;
pub const Vec4f = vec4.Vec4f;
pub const dot3 = vec4.dot3;
pub const squaredLength3 = vec4.squaredLength3;
pub const length3 = vec4.length3;
pub const squaredDistance3 = vec4.squaredDistance3;
pub const distance3 = vec4.distance3;
pub const normalize3 = vec4.normalize3;
pub const reciprocal3 = vec4.reciprocal3;
pub const cross3 = vec4.cross3;
pub const reflect3 = vec4.reflect3;
pub const orthonormalBasis3 = vec4.orthonormalBasis3;
pub const tangent3 = vec4.tangent3;
pub const min4 = vec4.min4;
pub const max4 = vec4.max4;
pub const clamp4 = vec4.clamp4;
pub const hmin3 = vec4.hmin3;
pub const hmax3 = vec4.hmax3;
pub const hmin4 = vec4.hmin4;
pub const hmax4 = vec4.hmax4;
pub const indexMinComponent3 = vec4.indexMinComponent3;
pub const indexMaxComponent3 = vec4.indexMaxComponent3;
pub const average3 = vec4.average3;
pub const pow = vec4.pow;
pub const equal = vec4.equal;
pub const allLess4 = vec4.allLess4;
pub const allLessEqual4i = vec4.allLessEqual4i;
pub const anyLess4i = vec4.anyLess4i;
pub const allLessEqualZero3 = vec4.allLessEqualZero3;
pub const anyGreaterZero3 = vec4.anyGreaterZero3;
pub const anyGreaterZero4 = vec4.anyGreaterZero4;
pub const anyGreaterEqual4u = vec4.anyGreaterEqual4u;
pub const anyNaN3 = vec4.anyNaN3;
pub const anyNaN4 = vec4.anyNaN4;
pub const allFinite3 = vec4.allFinite3;
pub const allFinite4 = vec4.allFinite4;
pub const vec3fTo4f = vec4.vec3fTo4f;
pub const vec3bTo4f = vec4.vec3bTo4f;
pub const vec4fTo3f = vec4.vec4fTo3f;
pub const vec4fTo3b = vec4.vec4fTo3b;
pub const vec4fTo3h = vec4.vec4fTo3h;
pub const vec4fTo4h = vec4.vec4fTo4h;
pub const vec3hTo4f = vec4.vec3hTo4f;
pub const vec2fTo4f = vec4.vec2fTo4f;

pub const plane = @import("plane.zig");
pub const safe = @import("safe.zig");

const std = @import("std");

pub const pi_inv = 1.0 / std.math.pi;

pub fn degreesToRadians(degrees: anytype) @TypeOf(degrees) {
    return degrees * (std.math.pi / 180.0);
}

pub fn radiansToDegrees(radians: anytype) @TypeOf(radians) {
    return radians * (180.0 / std.math.pi);
}

pub inline fn saturate(x: f32) f32 {
    return minmax.clamp(x, 0.0, 1.0);
}

pub inline fn lerp(a: anytype, b: anytype, t: anytype) @TypeOf(a, b, t) {
    switch (@typeInfo(@TypeOf(a))) {
        inline .comptime_float, .float => {
            const u = 1.0 - t;
            return @mulAdd(f32, u, a, t * b);
        },
        .vector => {
            const u = @as(@TypeOf(a), @splat(1.0)) - t;
            return @mulAdd(@TypeOf(a), u, a, t * b);
        },
        else => comptime unreachable,
    }
}

pub inline fn frac(x: anytype) @TypeOf(x) {
    return x - @floor(x);
}

pub inline fn floorfrac(v: anytype) struct { @TypeOf(v), @Vector(@typeInfo(@TypeOf(v)).vector.len, i32) } {
    const flv = @floor(v);
    return .{ v - flv, @intFromFloat(flv) };
}

pub fn pow2(x: f32) f32 {
    return x * x;
}

pub fn pow3(x: f32) f32 {
    const x2 = x * x;
    return x2 * x;
}

pub fn pow4(x: f32) f32 {
    const x2 = x * x;
    return x2 * x2;
}

pub fn pow5(x: f32) f32 {
    const x2 = x * x;
    const x4 = x2 * x2;
    return x4 * x;
}

pub fn pow20(x: f32) f32 {
    const x2 = x * x;
    const x4 = x2 * x2;
    const x8 = x4 * x4;
    const x16 = x8 * x8;
    return x16 * x4;
}

pub fn pow22(x: f32) f32 {
    const x2 = x * x;
    const x4 = x2 * x2;
    const x6 = x4 * x2;
    const x8 = x4 * x4;
    const x16 = x8 * x8;
    return x16 * x6;
}

pub inline fn bilinear(comptime T: type, c: [4]T, s: f32, t: f32) T {
    switch (@typeInfo(T)) {
        .float => {
            const _s = 1.0 - s;
            const _t = 1.0 - t;

            return _t * (_s * c[0] + s * c[1]) + t * (_s * c[2] + s * c[3]);
        },
        .vector => {
            const vs: T = @splat(s);
            const vt: T = @splat(t);

            const _s: T = @as(T, @splat(1.0)) - vs;
            const _t: T = @as(T, @splat(1.0)) - vt;

            return _t * (_s * c[0] + vs * c[1]) + vt * (_s * c[2] + vs * c[3]);
        },
        else => comptime unreachable,
    }
}

pub fn cubic1(c: *const [4]f32, t: f32) f32 {
    const t2 = t * t;
    const a0 = c[3] - c[2] - c[0] + c[1];
    const a1 = c[0] - c[1] - a0;
    const a2 = c[2] - c[0];
    const a3 = c[1];

    return a0 * t * t2 + a1 * t2 + a2 * t + a3;
}

pub fn bicubic1(c: [16]f32, s: f32, t: f32) f32 {
    const d: [4]f32 = .{
        cubic1(c[0..4], s),
        cubic1(c[4..8], s),
        cubic1(c[8..12], s),
        cubic1(c[12..16], s),
    };

    return cubic1(&d, t);
}

pub fn roundUp(comptime T: type, x: T, m: T) T {
    return ((x + m - 1) / m) * m;
}

pub inline fn solidAngleOfCone(c: f32) f32 {
    return (2.0 * std.math.pi) * (1.0 - c);
}

pub inline fn eq(x: f32, y: f32, comptime eps: f32) bool {
    return @abs(x - y) <= eps;
}

pub fn smoothstep(x: f32) f32 {
    return x * x * (3.0 - 2.0 * x);
}
