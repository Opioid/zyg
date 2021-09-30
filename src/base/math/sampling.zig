const Vec2f = @import("vector2.zig").Vec2f;
const Vec4f = @import("vector4.zig").Vec4f;

const std = @import("std");

pub fn diskConcentric(uv: Vec2f) Vec2f {
    const s = (uv * @splat(2, @as(f32, 2.0))) - @splat(2, @as(f32, 1.0));

    if (0.0 == s[0] and 0.0 == s[1]) {
        return @splat(2, @as(f32, 0.0));
    }

    var r: f32 = undefined;
    var theta: f32 = undefined;

    if (std.math.fabs(s[0]) > std.math.fabs(s[1])) {
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
