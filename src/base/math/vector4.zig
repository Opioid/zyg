const v2 = @import("vector2.zig");
const Vec2f = v2.Vec2f;
const v3 = @import("vector3.zig");
const Pack3b = v3.Pack3b;
const Pack3h = v3.Pack3h;
const Pack3f = v3.Pack3f;

const std = @import("std");

pub const Infinity = @splat(4, @bitCast(f32, @as(u32, 0x7F800000)));
pub const Neg_infinity = @splat(4, @bitCast(f32, @as(u32, 0xFF800000)));
pub const Min_normal = @splat(4, @bitCast(f32, @as(u32, 0x00800000)));

pub fn Vec4(comptime T: type) type {
    return struct {
        v: [4]T = undefined,

        pub fn init1(s: T) Vec4(T) {
            return .{ .v = [4]T{ s, s, s, s } };
        }

        pub fn init3(x: T, y: T, z: T) Vec4(T) {
            return .{ .v = [4]T{ x, y, z, 0.0 } };
        }

        pub fn init4(x: T, y: T, z: T, w: T) Vec4(T) {
            return .{ .v = [4]T{ x, y, z, w } };
        }

        pub fn addAssign3(self: *Vec4(T), other: Vec4(T)) void {
            self.v[0] += other.v[0];
            self.v[1] += other.v[1];
            self.v[2] += other.v[2];
        }

        pub fn addAssign4(self: *Vec4(T), other: Vec4(T)) void {
            self.v[0] += other.v[0];
            self.v[1] += other.v[1];
            self.v[2] += other.v[2];
            self.v[3] += other.v[3];
        }

        pub fn equal(a: Vec4(T), b: Vec4(T)) bool {
            return a.v[0] == b.v[0] and a.v[1] == b.v[1] and a.v[2] == b.v[2] and a.v[3] == b.v[3];
        }

        pub fn maxScalar(a: Vec4(T), s: T) Vec4(T) {
            return init3(
                std.math.max(a.v[0], s),
                std.math.max(a.v[1], s),
                std.math.max(a.v[2], s),
            );
        }
    };
}

pub const Vec4b = @Vector(4, u8);
pub const Pack4h = Vec4(f16);
pub const Pack4i = Vec4(i32);
pub const Vec4i = @Vector(4, i32);
pub const Vec4u = @Vector(4, u32);
pub const Pack4f = Vec4(f32);
pub const Vec4f = @Vector(4, f32);

pub fn dot3(a: Vec4f, b: Vec4f) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

pub fn squaredLength3(v: Vec4f) f32 {
    return dot3(v, v);
}

pub fn length3(v: Vec4f) f32 {
    return @sqrt(dot3(v, v));
}

pub fn rlength3(v: Vec4f) f32 {
    return 1.0 / length3(v);
}

pub fn squaredDistance3(a: Vec4f, b: Vec4f) f32 {
    return squaredLength3(a - b);
}

pub fn distance3(a: Vec4f, b: Vec4f) f32 {
    return length3(a - b);
}

pub fn normalize3(v: Vec4f) Vec4f {
    const i = 1.0 / length3(v);
    return @splat(4, i) * v;
}

pub fn reciprocal3(v: Vec4f) Vec4f {
    return @splat(4, @as(f32, 1.0)) / v;
}

pub fn cross3(a: Vec4f, b: Vec4f) Vec4f {
    // return .{
    //     a[1] * b[2] - a[2] * b[1],
    //     a[2] * b[0] - a[0] * b[2],
    //     a[0] * b[1] - a[1] * b[0],
    //     0.0,
    // };

    var tmp0 = @shuffle(f32, b, b, [_]i32{ 1, 2, 0, 3 });
    var tmp1 = @shuffle(f32, a, a, [_]i32{ 1, 2, 0, 3 });

    tmp0 = tmp0 * a;
    tmp1 = tmp1 * b;

    const tmp2 = tmp0 - tmp1;

    return @shuffle(f32, tmp2, tmp2, [_]i32{ 1, 2, 0, 3 });
}

pub fn reflect3(n: Vec4f, v: Vec4f) Vec4f {
    return @splat(4, 2.0 * dot3(v, n)) * n - v;
}

pub fn orthonormalBasis3(n: Vec4f) [2]Vec4f {
    // Building an Orthonormal Basis, Revisited
    // http://jcgt.org/published/0006/01/01/

    const sign = std.math.copysign(@as(f32, 1.0), n[2]);
    const c = -1.0 / (sign + n[2]);
    const d = n[0] * n[1] * c;

    return .{
        .{ 1.0 + sign * n[0] * n[0] * c, sign * d, -sign * n[0], 0.0 },
        .{ d, sign + n[1] * n[1] * c, -n[1], 0.0 },
    };
}

pub fn tangent3(n: Vec4f) Vec4f {
    const sign = std.math.copysign(@as(f32, 1.0), n[2]);
    const c = -1.0 / (sign + n[2]);
    const d = n[0] * n[1] * c;

    return .{ 1.0 + sign * n[0] * n[0] * c, sign * d, -sign * n[0], 0.0 };
}

pub fn clamp(v: Vec4f, mi: f32, ma: f32) Vec4f {
    return @minimum(@maximum(v, @splat(4, mi)), @splat(4, ma));
}

pub fn minComponent3(v: Vec4f) f32 {
    return std.math.min(v[0], std.math.min(v[1], v[2]));
}

pub fn maxComponent3(v: Vec4f) f32 {
    return std.math.max(v[0], std.math.max(v[1], v[2]));
}

pub fn indexMinComponent3(v: Vec4f) u32 {
    if (v[0] < v[1]) {
        return if (v[0] < v[2]) 0 else 2;
    }

    return if (v[1] < v[2]) 1 else 2;
}

pub fn indexMaxComponent3(v: Vec4f) u32 {
    if (v[0] > v[1]) {
        return if (v[0] > v[2]) 0 else 2;
    }

    return if (v[1] > v[2]) 1 else 2;
}

pub fn average3(v: Vec4f) f32 {
    return (v[0] + v[1] + v[2]) / 3.0;
}

pub fn equal(a: Vec4f, b: Vec4f) bool {
    return @reduce(.And, a == b);
}

pub fn equal4i(a: Vec4i, b: Vec4i) bool {
    return @reduce(.And, a == b);
}

pub fn allLess4(a: Vec4f, b: Vec4f) bool {
    return @reduce(.And, a < b);
}

pub fn anyLess4i(a: Vec4i, b: Vec4i) bool {
    return @reduce(.Or, a < b);
}

pub fn anyGreaterZero3(v: Vec4f) bool {
    return @reduce(.Or, v > Vec4f{ 0.0, 0.0, 0.0, std.math.f32_max });
}

pub fn anyGreaterZero4(v: Vec4f) bool {
    return @reduce(.Or, v > @splat(4, @as(f32, 0.0)));
}

pub fn anyGreaterEqual4u(a: Vec4u, b: Vec4u) bool {
    return @reduce(.Or, a >= b);
}

pub fn anyNaN3(v: Vec4f) bool {
    if (std.math.isNan(v[0])) return true;
    if (std.math.isNan(v[1])) return true;
    if (std.math.isNan(v[2])) return true;

    return false;
}

pub fn anyNaN4(v: Vec4f) bool {
    if (std.math.isNan(v[0])) return true;
    if (std.math.isNan(v[1])) return true;
    if (std.math.isNan(v[2])) return true;
    if (std.math.isNan(v[3])) return true;

    return false;
}

pub fn allFinite3(v: Vec4f) bool {
    if (!std.math.isFinite(v[0])) return false;
    if (!std.math.isFinite(v[1])) return false;
    if (!std.math.isFinite(v[2])) return false;

    return true;
}

pub fn vec4fTo4i(v: Vec4f) Vec4i {
    return .{
        @floatToInt(i32, v[0]),
        @floatToInt(i32, v[1]),
        @floatToInt(i32, v[2]),
        @floatToInt(i32, v[3]),
    };
}

pub fn vec4iTo4f(v: Vec4i) Vec4f {
    return .{
        @intToFloat(f32, v[0]),
        @intToFloat(f32, v[1]),
        @intToFloat(f32, v[2]),
        @intToFloat(f32, v[3]),
    };
}

pub fn vec4iTo4u(v: Vec4i) Vec4u {
    return @bitCast(Vec4u, v);
}

pub fn vec3fTo4f(v: Pack3f) Vec4f {
    return .{ v.v[0], v.v[1], v.v[2], 0.0 };
}

pub fn vec3bTo4f(v: Pack3b) Vec4f {
    return .{
        @intToFloat(f32, v.v[0]),
        @intToFloat(f32, v.v[1]),
        @intToFloat(f32, v.v[2]),
        0.0,
    };
}

pub fn vec4bTo4f(v: Vec4b) Vec4f {
    return .{
        @intToFloat(f32, v[0]),
        @intToFloat(f32, v[1]),
        @intToFloat(f32, v[2]),
        @intToFloat(f32, v[3]),
    };
}

pub fn vec4fTo3f(v: Vec4f) Pack3f {
    return Pack3f.init3(v[0], v[1], v[2]);
}

pub fn vec4fTo3b(v: Vec4f) Pack3b {
    return Pack3b.init3(
        @floatToInt(u8, v[0]),
        @floatToInt(u8, v[1]),
        @floatToInt(u8, v[2]),
    );
}

pub fn vec4fTo3h(v: Vec4f) Pack3h {
    return Pack3h.init3(
        @floatCast(f16, v[0]),
        @floatCast(f16, v[1]),
        @floatCast(f16, v[2]),
    );
}

pub fn vec4fTo4h(v: Vec4f) Pack4h {
    return Pack4h.init4(
        @floatCast(f16, v[0]),
        @floatCast(f16, v[1]),
        @floatCast(f16, v[2]),
        @floatCast(f16, v[3]),
    );
}

pub fn vec4fTo4b(v: Vec4f) Vec4b {
    return .{
        @floatToInt(u8, v[0]),
        @floatToInt(u8, v[1]),
        @floatToInt(u8, v[2]),
        @floatToInt(u8, v[3]),
    };
}

pub fn vec3hTo4f(v: Pack3h) Vec4f {
    return .{
        @floatCast(f32, v.v[0]),
        @floatCast(f32, v.v[1]),
        @floatCast(f32, v.v[2]),
        0.0,
    };
}

pub fn vec2fTo4f(v: Vec2f) Vec4f {
    return .{ v[0], v[1], 0.0, 0.0 };
}
