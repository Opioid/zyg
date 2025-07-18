const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Look = enum {
    Default,
    Substitute,
    Golden,
    Punchy,
};

fn sRGBtoAGX(srgb: Vec4f) Vec4f {
    return .{
        0.8424790622530940 * srgb[0] + 0.0784335999999992 * srgb[1] + 0.0792237451477643 * srgb[2],
        0.0423282422610123 * srgb[0] + 0.8784686364697720 * srgb[1] + 0.0791661274605434 * srgb[2],
        0.0423756549057051 * srgb[0] + 0.0784336000000000 * srgb[1] + 0.8791429737931040 * srgb[2],
        0.0,
    };
}

pub fn agx(srgb: Vec4f) Vec4f {
    const min_ev: Vec4f = @splat(-12.47393);
    const max_ev: Vec4f = @splat(4.026069);

    // Input transform (inset)
    var val = sRGBtoAGX(srgb);

    // Log2 space encoding
    val = math.clamp4(@log2(val), min_ev, max_ev);
    val = (val - min_ev) / (max_ev - min_ev);

    // Apply sigmoid function approximation
    return math.max4(agxDefaultContrastApprox(val), @splat(0.0));
}

pub fn look(val: Vec4f, l: Look) Vec4f {
    const lw = Vec4f{ 0.2126, 0.7152, 0.072, 0.0 };
    const luma: Vec4f = @splat(math.dot3(val, lw));

    // Default
    var slope: Vec4f = undefined;
    var power: Vec4f = undefined;
    var sat: Vec4f = undefined;

    if (.Substitute == l) {
        slope = @splat(1.0);
        power = @splat(1.1);
        sat = @splat(1.05);
    } else if (.Golden == l) {
        // Golden
        slope = .{ 1.0, 0.9, 0.5, 0.0 };
        power = @splat(0.8);
        sat = @splat(0.8);
    } else if (.Punchy == l) {
        // Punchy
        slope = @splat(1.0);
        power = @splat(1.35);
        sat = @splat(1.4);
    } else {
        slope = @splat(1.0);
        power = @splat(1.0);
        sat = @splat(1.0);
    }

    // ASC CDL
    const p = math.pow(val * slope, power);
    return luma + sat * (p - luma);
}

fn agxTosRGB(x: Vec4f) Vec4f {
    return .{
        1.19687900512017 * x[0] - 0.0980208811401368 * x[1] - 0.0990297440797205 * x[2],
        -0.0528968517574562 * x[0] + 1.15190312990417 * x[1] - 0.0989611768448433 * x[2],
        -0.0529716355144438 * x[0] - 0.0980434501171241 * x[1] + 1.15107367264116 * x[2],
        0.0,
    };
}

pub fn eotf(in: Vec4f) Vec4f {
    const val = agxTosRGB(in);

    // Not really sure if we should use piecewise function here instead
    // sRGB IEC 61966-2-1 2.2 Exponent Reference EOTF Display
    return math.pow(val, @splat(2.2));
}

// Mean error^2: 3.6705141e-06
fn agxDefaultContrastApprox(x: Vec4f) Vec4f {
    const x2 = x * x;
    const x4 = x2 * x2;

    return @as(Vec4f, @splat(15.5)) * x4 * x2 -
        @as(Vec4f, @splat(40.14)) * x4 * x +
        @as(Vec4f, @splat(31.96)) * x4 -
        @as(Vec4f, @splat(6.868)) * x2 * x +
        @as(Vec4f, @splat(0.4298)) * x2 +
        @as(Vec4f, @splat(0.1191)) * x -
        @as(Vec4f, @splat(0.00232));
}
