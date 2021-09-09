const Vec2f = @import("vector2.zig").Vec2f;
const Vec4f = @import("vector4.zig").Vec4f;

const std = @import("std");

pub fn diskConcentric(uv: Vec2f) Vec2f {
    const s = uv.mulScalar(2.0).subScalar(1.0);

    if (0.0 == s.v[0] and 0.0 == s.v[1]) {
        return Vec2f.init1(0.0);
    }

    var r: f32 = undefined;
    var theta: f32 = undefined;

    if (std.math.fabs(s.v[0]) > std.math.fabs(s.v[1])) {
        r = s.v[0];
        theta = (std.math.pi / 4.0) * (s.v[1] / s.v[0]);
    } else {
        r = s.v[1];
        theta = (std.math.pi / 2.0) - (std.math.pi / 4.0) * (s.v[0] / s.v[1]);
    }

    const sin_theta = @sin(theta);
    const cos_theta = @cos(theta);

    return Vec2f.init2(cos_theta * r, sin_theta * r);
}

pub fn hemisphereCosine(uv: Vec2f) Vec4f {
    const xy = diskConcentric(uv);
    const z = @sqrt(std.math.max(0.0, 1.0 - xy.v[0] * xy.v[0] - xy.v[1] * xy.v[1]));

    return Vec4f.init3(xy.v[0], xy.v[1], z);
}

pub fn orientedHemisphereCosine(uv: Vec2f, x: Vec4f, y: Vec4f, z: Vec4f) Vec4f {
    const xy = diskConcentric(uv);
    const za = @sqrt(std.math.max(0.0, 1.0 - xy.v[0] * xy.v[0] - xy.v[1] * xy.v[1]));

    return x.mulScalar3(xy.v[0]).add3(y.mulScalar3(xy.v[1])).add3(z.mulScalar3(za));
}
