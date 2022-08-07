const std = @import("std");

pub fn Vec3(comptime T: type) type {
    return struct {
        v: [3]T,

        pub fn init1(s: T) Vec3(T) {
            return .{ .v = [3]T{ s, s, s } };
        }

        pub fn init2(x: T, y: T) Vec3(T) {
            return .{ .v = [3]T{ x, y, 0 } };
        }

        pub fn init3(x: T, y: T, z: T) Vec3(T) {
            return .{ .v = [3]T{ x, y, z } };
        }

        pub fn add(a: Vec3(T), b: Vec3(T)) Vec3(T) {
            return init3(a.v[0] + b.v[0], a.v[1] + b.v[1], a.v[2] + b.v[2]);
        }

        pub fn addScalar(v: Vec3(T), s: T) Vec3(T) {
            return init3(v.v[0] + s, v.v[1] + s, v.v[2] + s);
        }

        pub fn addAssign(self: *Vec3(T), other: Vec3(T)) void {
            self.v[0] += other.v[0];
            self.v[1] += other.v[1];
            self.v[2] += other.v[2];
        }

        pub fn sub(a: Vec3(T), b: Vec3(T)) Vec3(T) {
            return init3(a.v[0] - b.v[0], a.v[1] - b.v[1], a.v[2] - b.v[2]);
        }

        pub fn subScalar(v: Vec3(T), s: T) Vec3(T) {
            return init3(v.v[0] - s, v.v[1] - s, v.v[2] - s);
        }

        pub fn min1(v: Vec3(T), s: T) Vec3(T) {
            return init3(std.math.min(v.v[0], s), std.math.min(v.v[1], s), std.math.min(v.v[2], s));
        }

        pub fn min3(a: Vec3(T), b: Vec3(T)) Vec3(T) {
            return init3(std.math.min(a.v[0], b.v[0]), std.math.min(a.v[1], b.v[1]), std.math.min(a.v[2], b.v[2]));
        }

        pub fn max1(v: Vec3(T), s: T) Vec3(T) {
            return init3(std.math.max(v.v[0], s), std.math.max(v.v[1], s), std.math.max(v.v[2], s));
        }

        pub fn max3(a: Vec3(T), b: Vec3(T)) Vec3(T) {
            return init3(std.math.max(a.v[0], b.v[0]), std.math.max(a.v[1], b.v[1]), std.math.max(a.v[2], b.v[2]));
        }

        pub fn anyLess1(v: Vec3(T), s: T) bool {
            return v.v[0] < s or v.v[1] < s or v.v[2] < s;
        }

        pub fn equal(a: Vec3(T), b: Vec3(T)) bool {
            return a.v[0] == b.v[0] and a.v[1] == b.v[1] and a.v[2] == b.v[2];
        }

        pub fn anyGreaterEqual3(a: Vec3(T), b: Vec3(T)) bool {
            if (a.v[0] >= b.v[0]) return true;
            if (a.v[1] >= b.v[1]) return true;
            if (a.v[2] >= b.v[2]) return true;

            return false;
        }
    };
}

pub const Pack3b = Vec3(u8);
pub const Vec3i = Vec3(i32);
pub const Pack3h = Vec3(f16);
pub const Pack3f = Vec3(f32);
