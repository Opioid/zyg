const std = @import("std");

pub fn Vec2(comptime T: type) type {
    return struct {
        v: [2]T,

        pub fn init1(s: T) Vec2(T) {
            return .{ .v = [2]T{ s, s } };
        }

        pub fn init2(x: T, y: T) Vec2(T) {
            return .{ .v = [2]T{ x, y } };
        }

        pub fn add(a: Vec2(T), b: Vec2(T)) Vec2(T) {
            return init2(a.v[0] + b.v[0], a.v[1] + b.v[1]);
        }

        pub fn addAssign(self: *Vec2(T), other: Vec2(T)) void {
            self.v[0] += other.v[0];
            self.v[1] += other.v[1];
        }

        pub fn addScalar(self: Vec2(T), s: T) Vec2(T) {
            return init2(self.v[0] + s, self.v[1] + s);
        }

        pub fn addAssignScalar(self: *Vec2(T), s: T) void {
            self.v[0] += s;
            self.v[1] += s;
        }

        pub fn sub(a: Vec2(T), b: Vec2(T)) Vec2(T) {
            return init2(a.v[0] - b.v[0], a.v[1] - b.v[1]);
        }

        pub fn subScalar(self: Vec2(T), s: T) Vec2(T) {
            return init2(self.v[0] - s, self.v[1] - s);
        }

        pub fn mulScalar(self: Vec2(T), s: T) Vec2(T) {
            return init2(self.v[0] * s, self.v[1] * s);
        }

        pub fn mulAssignScalar(self: *Vec2(T), s: T) void {
            self.v[0] *= s;
            self.v[1] *= s;
        }

        pub fn dot(a: Vec2(T), b: Vec2(T)) T {
            return a.v[0] * b.v[0] + a.v[1] * b.v[1];
        }

        pub fn toVec2f(v: Vec2(i32)) Vec2f {
            return .{ @intToFloat(f32, v.v[0]), @intToFloat(f32, v.v[1]) };
        }

        pub fn min(a: Vec2(T), b: Vec2(T)) Vec2(T) {
            return init2(std.math.min(a.v[0], b.v[0]), std.math.min(a.v[1], b.v[1]));
        }
    };
}

pub const Vec2b = Vec2(u8);
pub const Vec2i = Vec2(i32);

pub const Vec2f = std.meta.Vector(2, f32);

pub fn dot2(a: Vec2f, b: Vec2f) f32 {
    return a[0] * b[0] + a[1] * b[1];
}
