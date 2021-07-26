pub fn Vec2(comptime T: type) type {
    return struct {
        v: [2]T,

        pub fn init1(s: T) Vec2(T) {
            return .{ .v = [2]T{ s, s } };
        }

        pub fn init2(x: T, y: T) Vec2(T) {
            return .{ .v = [2]T{ x, y } };
        }

        pub fn subScalar(self: Vec2(T), s: T) Vec2(T) {
            return init2(self.v[0] - s, self.v[1] - s);
        }

        pub fn add(a: Vec2(T), b: Vec2(T)) Vec2(T) {
            return init2(a.v[0] + b.v[0], a.v[1] + b.v[1]);
        }

        pub fn mulScalar(self: Vec2(T), s: T) Vec2(T) {
            return init2(self.v[0] * s, self.v[1] * s);
        }

        pub fn toVec2f(v: Vec2(i32)) Vec2(f32) {
            return Vec2(f32).init2(@intToFloat(f32, v.v[0]), @intToFloat(f32, v.v[1]));
        }
    };
}

pub const Vec2i = Vec2(i32);
pub const Vec2f = Vec2(f32);
