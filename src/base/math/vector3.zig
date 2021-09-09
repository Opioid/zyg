const Vec2 = @import("vector2.zig").Vec2;

pub fn Vec3(comptime T: type) type {
    return struct {
        v: [3]T,

        pub fn init1(s: T) Vec3(T) {
            return .{ .v = [3]T{ s, s, s } };
        }

        pub fn init2(x: T, y: T) Vec3(T) {
            return .{ .v = [3]T{ x, y, 0 } };
        }

        pub fn init2_1(vxy: Vec2(T), z: T) Vec3(T) {
            return .{ .v = [3]T{ vxy.v[0], vxy.v[1], z } };
        }

        pub fn init3(x: T, y: T, z: T) Vec3(T) {
            return .{ .v = [3]T{ x, y, z } };
        }

        pub fn xy(self: Vec3(T)) Vec2(T) {
            return Vec2(T).init2(self.v[0], self.v[1]);
        }

        pub fn add(a: Vec3(T), b: Vec3(T)) Vec3(T) {
            return init3(a.v[0] + b.v[0], a.v[1] + b.v[1], a.v[2] + b.v[2]);
        }

        pub fn sub(a: Vec3(T), b: Vec3(T)) Vec3(T) {
            return init3(a.v[0] - b.v[0], a.v[1] - b.v[1], a.v[2] - b.v[2]);
        }

        pub fn mulScalar(v: Vec3(T), s: T) Vec3(T) {
            return init3(v.v[0] * s, v.v[1] * s, v.v[2] * s);
        }

        pub fn divScalar(v: Vec3(T), s: T) Vec3(T) {
            const is = 1.0 / s;
            return init3(v.v[0] * is, v.v[1] * is, v.v[2] * is);
        }

        pub fn dot(a: Vec3(T), b: Vec3(T)) T {
            return a.v[0] * b.v[0] + a.v[1] * b.v[1] + a.v[2] * b.v[2];
        }

        pub fn length(v: Vec3(T)) T {
            return @sqrt(v.dot(v));
        }

        pub fn normalize(v: Vec3(T)) Vec3(T) {
            return v.divScalar(length(v));
        }
    };
}

pub const Vec3b = Vec3(u8);
pub const Vec3i = Vec3(i32);
pub const Vec3f = Vec3(f32);
