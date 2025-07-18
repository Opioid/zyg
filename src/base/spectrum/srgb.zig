const Vec4f = @import("../math/vector4.zig").Vec4f;

const std = @import("std");

// convert sRGB linear value to sRGB gamma value
pub fn linearToGamma(c: f32) f32 {
    if (c <= 0.0) {
        return 0.0;
    } else if (c < 0.0031308) {
        return 12.92 * c;
    } else if (c < 1.0) {
        return 1.055 * std.math.pow(f32, c, 1.0 / 2.4) - 0.055;
    }

    return 1.0;
}

pub fn linearToGamma3(c: Vec4f) Vec4f {
    return .{
        linearToGamma(c[0]),
        linearToGamma(c[1]),
        linearToGamma(c[2]),
        0.0,
    };
}

// convert sRGB gamma value to sRGB linear value
pub fn gammaToLinear(c: f32) f32 {
    if (c <= 0.0) {
        return 0.0;
    } else if (c < 0.04045) {
        return c / 12.92;
    } else if (c < 1.0) {
        return std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
    }

    return 1.0;
}
