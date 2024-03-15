const math = @import("minmax.zig");
const v2 = @import("vector2.zig");
const Vec2f = v2.Vec2f;
const v3 = @import("vector3.zig");
const Pack3b = v3.Pack3b;
const Pack3h = v3.Pack3h;
const Pack3f = v3.Pack3f;

const std = @import("std");

pub fn Vec4(comptime T: type) type {
    return extern struct {
        v: [4]T = undefined,

        pub fn init1(s: T) Vec4(T) {
            return .{ .v = [4]T{ s, s, s, s } };
        }

        pub fn init4(x: T, y: T, z: T, w: T) Vec4(T) {
            return .{ .v = [4]T{ x, y, z, w } };
        }
    };
}

pub const Pack4h = Vec4(f16);
pub const Pack4i = Vec4(i32);
pub const Pack4f = Vec4(f32);

pub const Vec4b = @Vector(4, u8);
pub const Vec4i = @Vector(4, i32);
pub const Vec4u = @Vector(4, u32);
pub const Vec4f = @Vector(4, f32);

pub inline fn dot3(a: Vec4f, b: Vec4f) f32 {
    const ab = a * b;
    return ab[0] + ab[1] + ab[2];
}

pub inline fn squaredLength3(v: Vec4f) f32 {
    return dot3(v, v);
}

pub inline fn length3(v: Vec4f) f32 {
    return @sqrt(dot3(v, v));
}

pub inline fn squaredDistance3(a: Vec4f, b: Vec4f) f32 {
    return squaredLength3(a - b);
}

pub inline fn distance3(a: Vec4f, b: Vec4f) f32 {
    return length3(a - b);
}

pub inline fn normalize3(v: Vec4f) Vec4f {
    return v / @as(Vec4f, @splat(length3(v)));
}

pub inline fn reciprocal3(v: Vec4f) Vec4f {
    return @as(Vec4f, @splat(1.0)) / v;
}

pub inline fn cross3(a: Vec4f, b: Vec4f) Vec4f {
    // return .{
    //     a[1] * b[2] - a[2] * b[1],
    //     a[2] * b[0] - a[0] * b[2],
    //     a[0] * b[1] - a[1] * b[0],
    //     0.0,
    // };

    var tmp0 = @shuffle(f32, b, undefined, [_]i32{ 1, 2, 0, 3 });
    var tmp1 = @shuffle(f32, a, undefined, [_]i32{ 1, 2, 0, 3 });

    tmp0 = tmp0 * a;
    tmp1 = tmp1 * b;

    const tmp2 = tmp0 - tmp1;

    return @shuffle(f32, tmp2, undefined, [_]i32{ 1, 2, 0, 3 });
}

pub inline fn reflect3(n: Vec4f, v: Vec4f) Vec4f {
    return @as(Vec4f, @splat(2.0 * dot3(v, n))) * n - v;
}

pub inline fn orthonormalBasis3(n: Vec4f) [2]Vec4f {
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

pub inline fn tangent3(n: Vec4f) Vec4f {
    const sign = std.math.copysign(@as(f32, 1.0), n[2]);
    const c = -1.0 / (sign + n[2]);
    const d = n[0] * n[1] * c;

    return .{ 1.0 + sign * n[0] * n[0] * c, sign * d, -sign * n[0], 0.0 };
}

pub inline fn min4(a: Vec4f, b: Vec4f) Vec4f {
    return .{
        math.min(a[0], b[0]),
        math.min(a[1], b[1]),
        math.min(a[2], b[2]),
        math.min(a[3], b[3]),
    };
}

pub inline fn max4(a: Vec4f, b: Vec4f) Vec4f {
    return .{
        math.max(a[0], b[0]),
        math.max(a[1], b[1]),
        math.max(a[2], b[2]),
        math.max(a[3], b[3]),
    };
}

pub inline fn clamp4(v: Vec4f, mi: f32, ma: f32) Vec4f {
    return min4(max4(v, @splat(mi)), @splat(ma));
}

pub inline fn hmin3(v: Vec4f) f32 {
    return math.min(v[0], math.min(v[1], v[2]));
}

pub inline fn hmax3(v: Vec4f) f32 {
    return math.max(v[0], math.max(v[1], v[2]));
}

pub inline fn indexMinComponent3(v: Vec4f) u32 {
    if (v[0] < v[1]) {
        return if (v[0] < v[2]) 0 else 2;
    }

    return if (v[1] < v[2]) 1 else 2;
}

pub inline fn indexMaxComponent3(v: Vec4f) u32 {
    if (v[0] > v[1]) {
        return if (v[0] > v[2]) 0 else 2;
    }

    return if (v[1] > v[2]) 1 else 2;
}

pub inline fn average3(v: Vec4f) f32 {
    return (v[0] + v[1] + v[2]) / 3.0;
}

pub inline fn pow(a: Vec4f, b: Vec4f) Vec4f {
    return .{
        std.math.pow(f32, a[0], b[0]),
        std.math.pow(f32, a[1], b[1]),
        std.math.pow(f32, a[2], b[2]),
        std.math.pow(f32, a[3], b[3]),
    };
}

pub inline fn equal(a: anytype, b: @TypeOf(a)) bool {
    return @reduce(.And, a == b);
}

pub inline fn allLess4(a: Vec4f, b: Vec4f) bool {
    return @reduce(.And, a < b);
}

pub inline fn anyLess4i(a: Vec4i, b: Vec4i) bool {
    return @reduce(.Or, a < b);
}

pub inline fn allLessEqualZero3(v: Vec4f) bool {
    return @reduce(.And, v <= Vec4f{ 0.0, 0.0, 0.0, std.math.floatMax(f32) });
}

pub inline fn anyGreaterZero3(v: Vec4f) bool {
    return @reduce(.Or, v > Vec4f{ 0.0, 0.0, 0.0, std.math.floatMax(f32) });
}

pub inline fn anyGreaterZero4(v: Vec4f) bool {
    return @reduce(.Or, v > @as(Vec4f, @splat(0.0)));
}

pub inline fn anyGreaterEqual4u(a: Vec4u, b: Vec4u) bool {
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

pub inline fn vec3fTo4f(v: Pack3f) Vec4f {
    return .{ v.v[0], v.v[1], v.v[2], 0.0 };
}

pub inline fn vec3bTo4f(v: Pack3b) Vec4f {
    return .{
        @floatFromInt(v.v[0]),
        @floatFromInt(v.v[1]),
        @floatFromInt(v.v[2]),
        0.0,
    };
}

pub inline fn vec4fTo3f(v: Vec4f) Pack3f {
    return Pack3f.init3(v[0], v[1], v[2]);
}

pub inline fn vec4fTo3b(v: Vec4f) Pack3b {
    return Pack3b.init3(
        @intFromFloat(v[0]),
        @intFromFloat(v[1]),
        @intFromFloat(v[2]),
    );
}

pub inline fn vec4fTo3h(v: Vec4f) Pack3h {
    return Pack3h.init3(
        @floatCast(v[0]),
        @floatCast(v[1]),
        @floatCast(v[2]),
    );
}

pub inline fn vec4fTo4h(v: Vec4f) Pack4h {
    return Pack4h.init4(
        @floatCast(v[0]),
        @floatCast(v[1]),
        @floatCast(v[2]),
        @floatCast(v[3]),
    );
}

pub inline fn vec3hTo4f(v: Pack3h) Vec4f {
    return .{
        @floatCast(v.v[0]),
        @floatCast(v.v[1]),
        @floatCast(v.v[2]),
        0.0,
    };
}

pub inline fn vec2fTo4f(v: Vec2f) Vec4f {
    return .{ v[0], v[1], 0.0, 0.0 };
}
