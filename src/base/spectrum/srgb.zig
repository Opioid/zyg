const Vec4f = @import("../math/vector4.zig").Vec4f;

const std = @import("std");

// convert sRGB linear value to sRGB gamma value
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

// convert sRGB gamma value to sRGB linear value
pub fn gammaToLinear_sRGB(c: f32) f32 {
    if (c <= 0.0) {
        return 0.0;
    } else if (c < 0.04045) {
        return c / 12.92;
    } else if (c < 1.0) {
        return std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
    }

    return 1.0;
}

pub fn gammaToLinear_sRGB3(c: Vec4f) Vec4f {
    return Vec4f.init3(gammaToLinear_sRGB(c.v[0]), gammaToLinear_sRGB(c.v[1]), gammaToLinear_sRGB(c.v[2]));
}

pub fn luminance(c: Vec4f) f32 {
    // https://github.com/ampas/aces-dev/blob/master/transforms/ctl/README-MATRIX.md
    return 0.2722287168 * c[0] + 0.6740817658 * c[1] + 0.0536895174 * c[2];
}
