usingnamespace @import("vector2.zig");

const std = @import("std");

pub fn Vec4(comptime T: type) type {
    return struct {
        v: [4]T = undefined,

        pub fn init1(s: T) Vec4(T) {
            return .{ .v = [4]T{ s, s, s, s } };
        }

        pub fn init2(x: T, y: T) Vec4(T) {
            return .{ .v = [4]T{ x, y, 0.0, 0.0 } };
        }

        pub fn init3(x: T, y: T, z: T) Vec4(T) {
            return .{ .v = [4]T{ x, y, z, 0.0 } };
        }

        pub fn init3_1(v: Vec4(T), s: T) Vec4(T) {
            return .{ .v = [4]T{ v.v[0], v.v[1], v.v[2], s } };
        }

        pub fn init4(x: T, y: T, z: T, w: T) Vec4(T) {
            return .{ .v = [4]T{ x, y, z, w } };
        }

        pub fn init2_2(a: Vec2(T), b: Vec2(T)) Vec4(T) {
            return .{ .v = [4]T{ a.v[0], a.v[1], b.v[0], b.v[1] } };
        }

        pub fn xy(v: Vec4(T)) Vec2(T) {
            return Vec2(T).init2(v.v[0], v.v[1]);
        }

        pub fn zw(v: Vec4(T)) Vec2(T) {
            return Vec2(T).init2(v.v[2], v.v[3]);
        }

        pub fn add3(a: Vec4(T), b: Vec4(T)) Vec4(T) {
            return init3(a.v[0] + b.v[0], a.v[1] + b.v[1], a.v[2] + b.v[2]);
        }

        pub fn addAssign3(self: *Vec4(T), other: Vec4(T)) void {
            self.v[0] += other.v[0];
            self.v[1] += other.v[1];
            self.v[2] += other.v[2];
        }

        pub fn add4(a: Vec4(T), b: Vec4(T)) Vec4(T) {
            return init4(a.v[0] + b.v[0], a.v[1] + b.v[1], a.v[2] + b.v[2], a.v[3] + b.v[3]);
        }

        pub fn addAssign4(self: *Vec4(T), other: Vec4(T)) void {
            self.v[0] += other.v[0];
            self.v[1] += other.v[1];
            self.v[2] += other.v[2];
            self.v[3] += other.v[3];
        }

        pub fn sub3(a: Vec4(T), b: Vec4(T)) Vec4(T) {
            return init3(a.v[0] - b.v[0], a.v[1] - b.v[1], a.v[2] - b.v[2]);
        }

        pub fn neg3(v: Vec4(T)) Vec4(T) {
            return init3(-v.v[0], -v.v[1], -v.v[2]);
        }

        pub fn neg4(v: Vec4(T)) Vec4(T) {
            return init4(-v.v[0], -v.v[1], -v.v[2], -v.v[3]);
        }

        pub fn mul3(a: Vec4(T), b: Vec4(T)) Vec4(T) {
            return init3(a.v[0] * b.v[0], a.v[1] * b.v[1], a.v[2] * b.v[2]);
        }

        pub fn mulAssign3(self: *Vec4(T), other: Vec4(T)) void {
            self.v[0] *= other.v[0];
            self.v[1] *= other.v[1];
            self.v[2] *= other.v[2];
        }

        pub fn div3(a: Vec4(T), b: Vec4(T)) Vec4(T) {
            return init3(a.v[0] / b.v[0], a.v[1] / b.v[1], a.v[2] / b.v[2]);
        }

        pub fn addScalar3(v: Vec4(T), s: T) Vec4(T) {
            return init3(v.v[0] + s, v.v[1] + s, v.v[2] + s);
        }

        pub fn subScalar3(v: Vec4(T), s: T) Vec4(T) {
            return init3(v.v[0] - s, v.v[1] - s, v.v[2] - s);
        }

        pub fn mulScalar3(v: Vec4(T), s: T) Vec4(T) {
            return init3(v.v[0] * s, v.v[1] * s, v.v[2] * s);
        }

        pub fn mulScalar4(v: Vec4(T), s: T) Vec4(T) {
            return init4(v.v[0] * s, v.v[1] * s, v.v[2] * s, v.v[3] * s);
        }

        pub fn divScalar3(v: Vec4(T), s: T) Vec4(T) {
            const is = 1.0 / s;
            return init3(v.v[0] * is, v.v[1] * is, v.v[2] * is);
        }

        pub fn divScalar4(v: Vec4(T), s: T) Vec4(T) {
            const is = 1.0 / s;
            return init4(v.v[0] * is, v.v[1] * is, v.v[2] * is, v.v[3] * is);
        }

        pub fn dot3(a: Vec4(T), b: Vec4(T)) T {
            return a.v[0] * b.v[0] + a.v[1] * b.v[1] + a.v[2] * b.v[2];
        }

        pub fn length3(v: Vec4(T)) T {
            return @sqrt(v.dot3(v));
        }

        pub fn normalize3(v: Vec4(T)) Vec4(T) {
            return v.divScalar3(length3(v));
        }

        pub fn reciprocal3(v: Vec4(T)) Vec4(T) {
            return init3(1.0 / v.v[0], 1.0 / v.v[1], 1.0 / v.v[2]);
        }

        pub fn cross3(a: Vec4(T), b: Vec4(T)) Vec4(T) {
            return init3(
                a.v[1] * b.v[2] - a.v[2] * b.v[1],
                a.v[2] * b.v[0] - a.v[0] * b.v[2],
                a.v[0] * b.v[1] - a.v[1] * b.v[0],
            );
        }

        pub fn equals3(a: Vec4(T), b: Vec4(T)) bool {
            return a.v[0] == b.v[0] and a.v[1] == b.v[1] and a.v[2] == b.v[2];
        }

        pub fn min3(a: Vec4(T), b: Vec4(T)) Vec4(T) {
            return init3(
                std.math.min(a.v[0], b.v[0]),
                std.math.min(a.v[1], b.v[1]),
                std.math.min(a.v[2], b.v[2]),
            );
        }

        pub fn max3(a: Vec4(T), b: Vec4(T)) Vec4(T) {
            return init3(
                std.math.max(a.v[0], b.v[0]),
                std.math.max(a.v[1], b.v[1]),
                std.math.max(a.v[2], b.v[2]),
            );
        }

        pub fn indexMaxComponent3(v: Vec4(T)) u32 {
            if (v.v[0] > v.v[1]) {
                return if (v.v[0] > v.v[2]) 0 else 2;
            }

            return if (v.v[1] > v.v[2]) 1 else 2;
        }

        pub fn tangent3(n: Vec4(T)) Vec4(T) {
            const sign = std.math.copysign(f32, 1.0, n.v[2]);
            const c = -1.0 / (sign + n.v[2]);
            const d = n.v[0] * n.v[1] * c;

            return init3(1.0 + sign * n.v[0] * n.v[0], sign * d, -sign * n.v[0]);
        }

        pub fn toVec4i(v: Vec4(f32)) Vec4(i32) {
            return Vec4(i32).init4(
                @floatToInt(i32, v.v[0]),
                @floatToInt(i32, v.v[1]),
                @floatToInt(i32, v.v[2]),
                @floatToInt(i32, v.v[3]),
            );
        }
    };
}

pub const Vec4i = Vec4(i32);
pub const Vec4f = Vec4(f32);

// pub fn vec2iTof(v: Vec2i) Vec2f {
//     return Vec2f.init2(@intToFloat(f32, v.v[0]), @intToFloat(f32, v.v[1]));
// }
