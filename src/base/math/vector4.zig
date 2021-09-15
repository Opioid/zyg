const Vec2 = @import("vector2.zig").Vec2;

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
    };
}

pub const Vec4i = Vec4(i32);
pub const Vec4f = std.meta.Vector(4, f32);

pub fn dot3(a: Vec4f, b: Vec4f) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

pub fn length3(v: Vec4f) f32 {
    return @sqrt(dot3(v, v));
}

pub fn normalize3(v: Vec4f) Vec4f {
    const i = 1.0 / length3(v);
    return @splat(4, i) * v;
}

pub fn reciprocal3(v: Vec4f) Vec4f {
    return @splat(4, @as(f32, 1.0)) / v;
}

pub fn cross3(a: Vec4f, b: Vec4f) Vec4f {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
        0.0,
    };
}

pub fn reflect3(n: Vec4f, v: Vec4f) Vec4f {
    return @splat(4, 2.0 * dot3(v, n)) * n - v;
}

pub fn orthonormalBasis3(n: Vec4f) [2]Vec4f {
    // Building an Orthonormal Basis, Revisited
    // http://jcgt.org/published/0006/01/01/

    const sign = std.math.copysign(f32, 1.0, n[2]);
    const c = -1.0 / (sign + n[2]);
    const d = n[0] * n[1] * c;

    return .{
        .{ 1.0 + sign * n[0] * n[0] * c, sign * d, -sign * n[0], 0.0 },
        .{ d, sign + n[1] * n[1] * c, -n[1], 0.0 },
    };
}

pub fn tangent3(n: Vec4f) Vec4f {
    const sign = std.math.copysign(f32, 1.0, n[2]);
    const c = -1.0 / (sign + n[2]);
    const d = n[0] * n[1] * c;

    return .{ 1.0 + sign * n[0] * n[0] * c, sign * d, -sign * n[0], 0.0 };
}

pub fn min3(a: Vec4f, b: Vec4f) Vec4f {
    return .{
        std.math.min(a[0], b[0]),
        std.math.min(a[1], b[1]),
        std.math.min(a[2], b[2]),
        0.0,
    };
}

pub fn max3(a: Vec4f, b: Vec4f) Vec4f {
    return .{
        std.math.max(a[0], b[0]),
        std.math.max(a[1], b[1]),
        std.math.max(a[2], b[2]),
        0.0,
    };
}

pub fn indexMaxComponent3(v: Vec4f) u32 {
    if (v[0] > v[1]) {
        return if (v[0] > v[2]) 0 else 2;
    }

    return if (v[1] > v[2]) 1 else 2;
}

pub fn vec4f_to_i(v: Vec4f) Vec4(i32) {
    return Vec4(i32).init4(
        @floatToInt(i32, v[0]),
        @floatToInt(i32, v[1]),
        @floatToInt(i32, v[2]),
        @floatToInt(i32, v[3]),
    );
}
