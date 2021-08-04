const Vec4f = @import("../math/vector4.zig").Vec4f;

const std = @import("std");

pub fn linearToGamma_sRGB(c: f32) f32 {
    if (c <= 0.0) {
        return 0.0;
    } else if (c < 0.0031308) {
        return 12.92 * c;
    } else if (c < 1.0) {
        return 1.055 * std.math.pow(f32, c, 1.0 / 2.4) - 0.055;
    }

    return 1.0;
}

pub fn linearToGamma_sRGB3(c: Vec4f) Vec4f {
    return Vec4f.init3(linearToGamma_sRGB(c.v[0]), linearToGamma_sRGB(c.v[1]), linearToGamma_sRGB(c.v[2]));
}

pub fn linearToGamma_sRGB4(c: Vec4f) Vec4f {
    return Vec4f.init4(linearToGamma_sRGB(c.v[0]), linearToGamma_sRGB(c.v[1]), linearToGamma_sRGB(c.v[2]), c.v[3]);
}
