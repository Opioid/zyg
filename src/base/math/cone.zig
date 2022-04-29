const math = @import("vector4.zig");
const Vec4f = math.Vec4f;
const Mat3x3 = @import("matrix3x3.zig").Mat3x3;

const std = @import("std");

pub fn merge(ap: Vec4f, bp: Vec4f) Vec4f {
    var a = ap;
    var b = bp;

    if (math.equal(@splat(4, @as(f32, 1.0)), a)) {
        return b;
    }

    if (math.equal(a, b)) {
        return a;
    }

    var a_angle = std.math.acos(a[3]);
    var b_angle = std.math.acos(b[3]);

    if (b_angle > a_angle) {
        std.mem.swap(Vec4f, &a, &b);
        std.mem.swap(f32, &a_angle, &b_angle);
    }

    const d_angle = std.math.acos(std.math.clamp(math.dot3(a, b), -1.0, 1.0));

    if (std.math.min(d_angle + b_angle, std.math.pi) <= a_angle) {
        return a;
    }

    const o_angle = (a_angle + d_angle + b_angle) / 2.0;
    if (o_angle >= std.math.pi) {
        return .{ a[0], a[1], a[2], -1.0 };
    }

    const r_angle = o_angle - a_angle;
    const rot = Mat3x3.initRotation(math.normalize3(math.cross3(a, b)), r_angle);
    const axis = math.normalize3(rot.transformVector(a));

    return .{ axis[0], axis[1], axis[2], @cos(o_angle) };
}

pub fn transform(m: Mat3x3, v: Vec4f) Vec4f {
    return .{
        v[0] * m.r[0][0] + v[1] * m.r[1][0] + v[2] * m.r[2][0],
        v[0] * m.r[0][1] + v[1] * m.r[1][1] + v[2] * m.r[2][1],
        v[0] * m.r[0][2] + v[1] * m.r[1][2] + v[2] * m.r[2][2],
        v[3],
    };
}
