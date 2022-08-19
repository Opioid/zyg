pub fn Vec3(comptime T: type) type {
    return extern struct {
        v: [3]T,

        pub fn init1(s: T) Vec3(T) {
            return .{ .v = [3]T{ s, s, s } };
        }

        pub fn init3(x: T, y: T, z: T) Vec3(T) {
            return .{ .v = [3]T{ x, y, z } };
        }
    };
}

pub const Pack3b = Vec3(u8);
pub const Pack3h = Vec3(f16);
pub const Pack3f = Vec3(f32);
