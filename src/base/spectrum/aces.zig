const Vec4f = @import("../math/vector4.zig").Vec4f;

// Some matrices are from the internet, e.g:
// https://www.shadertoy.com/view/WltSRB
// https://github.com/ampas/aces-dev/blob/master/transforms/ctl/README-MATRIX.md
// Others were generated with aces.py

// sRGB => XYZ => D65_2_D60 => AP1
pub fn sRGBtoAP1(srgb: Vec4f) Vec4f {
    return .{
        0.61309732 * srgb[0] + 0.33952285 * srgb[1] + 0.04737928 * srgb[2],
        0.07019422 * srgb[0] + 0.91635557 * srgb[1] + 0.01345259 * srgb[2],
        0.02061560 * srgb[0] + 0.10956983 * srgb[1] + 0.86981512 * srgb[2],
        0.0,
    };
}

pub fn AP1tosRGB(srgb: Vec4f) Vec4f {
    return .{
        1.70505155 * srgb[0] - 0.62179068 * srgb[1] - 0.08325840 * srgb[2],
        -0.13025714 * srgb[0] + 1.14080289 * srgb[1] - 0.01054853 * srgb[2],
        -0.02400328 * srgb[0] - 0.12896877 * srgb[1] + 1.15297171 * srgb[2],
        0.0,
    };
}

pub fn AP1toRRT_SAT(acescg: Vec4f) Vec4f {
    return .{
        0.970889 * acescg[0] + 0.026963 * acescg[1] + 0.002148 * acescg[2],
        0.010889 * acescg[0] + 0.986963 * acescg[1] + 0.002148 * acescg[2],
        0.010889 * acescg[0] + 0.026963 * acescg[1] + 0.962148 * acescg[2],
        0.0,
    };
}

// sRGB => XYZ => D65_2_D60 => AP1 => RRT_SAT
pub fn sRGBtoRRT_SAT(srgb: Vec4f) Vec4f {
    return .{
        0.59719 * srgb[0] + 0.35458 * srgb[1] + 0.04823 * srgb[2],
        0.07600 * srgb[0] + 0.90834 * srgb[1] + 0.01566 * srgb[2],
        0.02840 * srgb[0] + 0.13383 * srgb[1] + 0.83777 * srgb[2],
        0.0,
    };
}

// ODT_SAT => XYZ => D60_2_D65 => sRGB
pub fn ODTSATtosRGB(odt: Vec4f) Vec4f {
    return .{
        1.60475 * odt[0] - 0.53108 * odt[1] - 0.07367 * odt[2],
        -0.10208 * odt[0] + 1.10813 * odt[1] - 0.00605 * odt[2],
        -0.00327 * odt[0] - 0.07276 * odt[1] + 1.07602 * odt[2],
        0.0,
    };
}

// https://www.shadertoy.com/view/WltSRB
pub fn RRTandODT(x: Vec4f) Vec4f {
    const a = x * (x + @as(Vec4f, @splat(0.0245786))) - @as(Vec4f, @splat(0.000090537));
    const b = x * (@as(Vec4f, @splat(0.983729)) * x + @as(Vec4f, @splat(0.4329510))) + @as(Vec4f, @splat(0.238081));
    return a / b;
}

// XYZ => D65_2_D60 => AP1
pub fn XYZtoAP1(xyz: Vec4f) Vec4f {
    return .{
        1.66058533 * xyz[0] - 0.31529556 * xyz[1] - 0.24150933 * xyz[2],
        -0.65992606 * xyz[0] + 1.60839147 * xyz[1] + 0.01729859 * xyz[2],
        0.00900257 * xyz[0] - 0.00356688 * xyz[1] + 0.91364331 * xyz[2],
        0.0,
    };
}
