const Vec2f = @import("vector2.zig").Vec2f;
const math = @import("vector4.zig");
const Vec4f = math.Vec4f;

const std = @import("std");

pub fn diskConcentric(uv: Vec2f) Vec2f {
    const s = (uv * @splat(2, @as(f32, 2.0))) - @splat(2, @as(f32, 1.0));

    if (0.0 == s[0] and 0.0 == s[1]) {
        return @splat(2, @as(f32, 0.0));
    }

    var r: f32 = undefined;
    var theta: f32 = undefined;

    if (@fabs(s[0]) > @fabs(s[1])) {
        r = s[0];
        theta = (std.math.pi / 4.0) * (s[1] / s[0]);
    } else {
        r = s[1];
        theta = (std.math.pi / 2.0) - (std.math.pi / 4.0) * (s[0] / s[1]);
    }

    const sin_theta = @sin(theta);
    const cos_theta = @cos(theta);

    return .{ cos_theta * r, sin_theta * r };
}

pub fn orientedDiskConcentric(uv: Vec2f, x: Vec4f, y: Vec4f) Vec4f {
    const d = diskConcentric(uv);
    return @splat(4, d[0]) * x + @splat(4, d[1]) * y;
}

// pub fn triangleUniform(uv: Vec2f) Vec2f {
//     const su = @sqrt(uv[0]);
//     return .{ 1.0 - su, uv[1] * su };
// }

// Eric Heitz: A Low-Distortion Map Between Triangle and Square
// https://drive.google.com/file/d/1J-183vt4BrN9wmqItECIjjLIKwm29qSg/view
pub fn triangleUniform(uv: Vec2f) Vec2f {
    if (uv[1] > uv[0]) {
        const x = 0.5 * uv[0];
        return .{ x, uv[1] - x };
    }

    const y = 0.5 * uv[1];
    return .{ uv[0] - y, y };
}

pub fn hemisphereCosine(uv: Vec2f) Vec4f {
    const xy = diskConcentric(uv);
    const z = @sqrt(std.math.max(0.0, 1.0 - xy[0] * xy[0] - xy[1] * xy[1]));

    return .{ xy[0], xy[1], z, 0.0 };
}

pub fn orientedHemisphereCosine(uv: Vec2f, x: Vec4f, y: Vec4f, z: Vec4f) Vec4f {
    const xy = diskConcentric(uv);
    const za = @sqrt(std.math.max(0.0, 1.0 - xy[0] * xy[0] - xy[1] * xy[1]));

    return @splat(4, xy[0]) * x + @splat(4, xy[1]) * y + @splat(4, za) * z;
}

pub fn orientedHemisphereUniform(uv: Vec2f, x: Vec4f, y: Vec4f, z: Vec4f) Vec4f {
    const za = 1.0 - uv[0];
    const r = @sqrt(std.math.max(0.0, 1.0 - za * za));
    const phi = uv[1] * (2.0 * std.math.pi);

    const sin_phi = @sin(phi);
    const cos_phi = @cos(phi);

    return @splat(4, cos_phi * r) * x + @splat(4, sin_phi * r) * y + @splat(4, za) * z;
}

pub fn sphereUniform(uv: Vec2f) Vec4f {
    const z = 1.0 - 2.0 * uv[0];
    const r = @sqrt(std.math.max(0.0, 1.0 - z * z));
    const phi = uv[1] * (2.0 * std.math.pi);

    const sin_phi = @sin(phi);
    const cos_phi = @cos(phi);

    return .{ cos_phi * r, sin_phi * r, z, 0.0 };
}

pub fn sphereDirection(sin_theta: f32, cos_theta: f32, phi: f32, x: Vec4f, y: Vec4f, z: Vec4f) Vec4f {
    const sin_phi = @sin(phi);
    const cos_phi = @cos(phi);

    return @splat(4, cos_phi * sin_theta) * x + @splat(4, sin_phi * sin_theta) * y + @splat(4, cos_theta) * z;
}

pub fn orientedConeUniform(uv: Vec2f, cos_theta_max: f32, x: Vec4f, y: Vec4f, z: Vec4f) Vec4f {
    const cos_theta = (1.0 - uv[0]) + (uv[0] * cos_theta_max);
    const sin_theta = @sqrt(1.0 - cos_theta * cos_theta);
    const phi = uv[1] * (2.0 * std.math.pi);

    const sin_phi = @sin(phi);
    const cos_phi = @cos(phi);

    return @splat(4, cos_phi * sin_theta) * x + @splat(4, sin_phi * sin_theta) * y + @splat(4, cos_theta) * z;
}

pub const Eps: f32 = 1.0e-20;

pub fn conePdfUniform(cos_theta_max: f32) f32 {
    return 1.0 / ((2.0 * std.math.pi) * std.math.max(1.0 - cos_theta_max, Eps));
}

fn signNotZero(v: Vec2f) Vec2f {
    return .{ std.math.copysign(@as(f32, 1.0), v[0]), std.math.copysign(@as(f32, 1.0), v[1]) };
}

pub fn octEncode(v: Vec4f) Vec2f {
    const linorm = @fabs(v[0]) + @fabs(v[1]) + @fabs(v[2]);
    var o = Vec2f{ v[0], v[1] } * @splat(2, 1.0 / linorm);

    if (v[2] >= 0.0) {
        return (@splat(2, @as(f32, 1.0)) - @fabs(Vec2f{ o[1], o[0] })) * signNotZero(Vec2f{ o[0], o[1] });
    }

    return o;
}

pub fn octDecode(o: Vec2f) Vec4f {
    var v = Vec4f{ o[0], o[1], -1.0 + @fabs(o[0]) + @fabs(o[1]), 0.0 };
    if (v[2] >= 0.0) {
        const xy = (@splat(2, @as(f32, 1.0)) - @fabs(Vec2f{ v[1], v[0] })) * signNotZero(Vec2f{ v[0], v[1] });
        v[0] = xy[0];
        v[1] = xy[1];
    }

    return math.normalize3(v);
}
