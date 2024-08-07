const Vec2f = @import("vector2.zig").Vec2f;
const math = @import("vector4.zig");
const Vec4f = math.Vec4f;
const mima = @import("minmax.zig");

const std = @import("std");

pub fn diskConcentric(uv: Vec2f) Vec2f {
    const s = (uv * @as(Vec2f, @splat(2.0))) - @as(Vec2f, @splat(1.0));

    if (0.0 == s[0] and 0.0 == s[1]) {
        return @splat(0.0);
    }

    var r: f32 = undefined;
    var theta: f32 = undefined;

    if (@abs(s[0]) > @abs(s[1])) {
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
    const z = @sqrt(mima.max(0.0, 1.0 - xy[0] * xy[0] - xy[1] * xy[1]));

    return .{ xy[0], xy[1], z, 0.0 };
}

pub fn hemisphereUniform(uv: Vec2f) Vec4f {
    const z = 1.0 - uv[0];
    const r = @sqrt(mima.max(0.0, 1.0 - z * z));

    const phi = uv[1] * (2.0 * std.math.pi);
    const sin_phi = @sin(phi);
    const cos_phi = @cos(phi);

    return .{ cos_phi * r, sin_phi * r, z, 0.0 };
}

pub fn sphereUniform(uv: Vec2f) Vec4f {
    const z = 1.0 - 2.0 * uv[0];
    const r = @sqrt(mima.max(0.0, 1.0 - z * z));

    const phi = uv[1] * (2.0 * std.math.pi);
    const sin_phi = @sin(phi);
    const cos_phi = @cos(phi);

    return .{ cos_phi * r, sin_phi * r, z, 0.0 };
}

pub fn sphereDirection(sin_theta: f32, cos_theta: f32, phi: f32) Vec4f {
    const sin_phi = @sin(phi);
    const cos_phi = @cos(phi);

    return .{ cos_phi * sin_theta, sin_phi * sin_theta, cos_theta, 0.0 };
}

pub fn coneUniform(uv: Vec2f, cos_theta_max: f32) Vec4f {
    const cos_theta = (1.0 - uv[0]) + (uv[0] * cos_theta_max);
    const sin_theta = @sqrt(mima.max(0.0, 1.0 - cos_theta * cos_theta));

    const phi = uv[1] * (2.0 * std.math.pi);
    const sin_phi = @sin(phi);
    const cos_phi = @cos(phi);

    return .{ cos_phi * sin_theta, sin_phi * sin_theta, cos_theta, 0.0 };
}

pub fn coneCosine(uv: Vec2f, cos_theta_max: f32) Vec4f {
    const xy = @as(Vec2f, @splat(@sqrt(1.0 - cos_theta_max * cos_theta_max))) * diskConcentric(uv);
    const za = @sqrt(mima.max(0.0, 1.0 - xy[0] * xy[0] - xy[1] * xy[1]));

    return .{ xy[0], xy[1], za, 0.0 };
}

pub fn conePdfUniform(one_minus_cos_theta_max: f32) f32 {
    const eps: f32 = comptime 1.0e-20;
    return 1.0 / ((2.0 * std.math.pi) * mima.max(one_minus_cos_theta_max, eps));
}

pub fn conePdfCosine(cos_theta_max: f32) f32 {
    return 1.0 / ((1.0 - (cos_theta_max * cos_theta_max)) * std.math.pi);
}

pub fn octEncode(v: Vec4f) Vec2f {
    const inorm = 1.0 / (@abs(v[0]) + @abs(v[1]) + @abs(v[2]));
    const t = mima.max(v[2], 0.0);

    return .{
        (v[0] + if (v[0] > 0.0) t else -t) * inorm,
        (v[1] + if (v[1] > 0.0) t else -t) * inorm,
    };
}

pub fn octDecode(o: Vec2f) Vec4f {
    var v = Vec4f{ o[0], o[1], -1.0 + @abs(o[0]) + @abs(o[1]), 0.0 };

    const t = mima.max(v[2], 0.0);

    v[0] += if (v[0] > 0.0) -t else t;
    v[1] += if (v[1] > 0.0) -t else t;

    return math.normalize3(v);
}
