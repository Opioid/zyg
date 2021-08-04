const Vec4f = @import("../math/vector4.zig").Vec4f;

// Some matrices are from the internet, e.g:
// https://www.shadertoy.com/view/WltSRB
// https://github.com/ampas/aces-dev/blob/master/transforms/ctl/README-MATRIX.md
// Others were generated with aces.py

// sRGB => XYZ => D65_2_D60 => AP1
pub fn sRGB_to_AP1(srgb: Vec4f) Vec4f {
    return Vec4f.init3(0.61309732 * srgb.v[0] + 0.33952285 * srgb.v[1] + 0.04737928 * srgb.v[2],
                  0.07019422 * srgb.v[0] + 0.91635557 * srgb.v[1] + 0.01345259 * srgb.v[2],
                  0.02061560 * srgb.v[0] + 0.10956983 * srgb.v[1] + 0.86981512 * srgb.v[2]);
}

pub fn AP1_to_sRGB(srgb: Vec4f) Vec4f {
    return Vec4f.init3(1.70505155 * srgb.v[0] - 0.62179068 * srgb.v[1] - 0.08325840 * srgb.v[2],
                  -0.13025714 * srgb.v[0] + 1.14080289 * srgb.v[1] - 0.01054853 * srgb.v[2],
                  -0.02400328 * srgb.v[0] - 0.12896877 * srgb.v[1] + 1.15297171 * srgb.v[2]);
}

pub fn AP1_to_RRT_SAT(acescg: Vec4f) Vec4f {
    return Vec4f.init3(0.970889 * acescg.v[0] + 0.026963 * acescg.v[1] + 0.002148 * acescg.v[2],
                  0.010889 * acescg.v[0] + 0.986963 * acescg.v[1] + 0.002148 * acescg.v[2],
                  0.010889 * acescg.v[0] + 0.026963 * acescg.v[1] + 0.962148 * acescg.v[2]);
}

// sRGB => XYZ => D65_2_D60 => AP1 => RRT_SAT
pub fn sRGB_to_RRT_SAT(srgb: Vec4f) Vec4f {
    return Vec4f.init3(0.59719 * srgb.v[0] + 0.35458 * srgb.v[1] + 0.04823 * srgb.v[2],
                  0.07600 * srgb.v[0] + 0.90834 * srgb.v[1] + 0.01566 * srgb.v[2],
                  0.02840 * srgb.v[0] + 0.13383 * srgb.v[1] + 0.83777 * srgb.v[2]);
}

// ODT_SAT => XYZ => D60_2_D65 => sRGB
pub fn ODT_SAT_to_sRGB(odt: Vec4f) Vec4f {
    return Vec4f.init3(1.60475 * odt.v[0] - 0.53108 * odt.v[1] - 0.07367 * odt.v[2],
                  -0.10208 * odt.v[0] + 1.10813 * odt.v[1] - 0.00605 * odt.v[2],
                  -0.00327 * odt.v[0] - 0.07276 * odt.v[1] + 1.07602 * odt.v[2]);
}

// https://www.shadertoy.com/view/WltSRB
pub fn  RRT_and_ODT(x: Vec4f) Vec4f {
    const a = (x.addScalar3(0.0245786).subScalar3(0.000090537)).mul3(x);
    const b = (x.mulScalar3(0.983729).addScalar3(0.4329510).addScalar3(0.238081)).mul3(x);
    return a.div3(b);
}

// XYZ => D65_2_D60 => AP1
pub fn XYZ_to_AP1(xyz: Vec4f) Vec4f {
    return Vec4f.init3(1.66058533 * xyz.v[0] - 0.31529556 * xyz.v[1] - 0.24150933 * xyz.v[2],
                  -0.65992606 * xyz.v[0] + 1.60839147 * xyz.v[1] + 0.01729859 * xyz.v[2],
                  +0.00900257 * xyz.v[0] - 0.00356688 * xyz.v[1] + 0.91364331 * xyz.v[2]);
}
