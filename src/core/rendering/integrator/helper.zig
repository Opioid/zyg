const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const LightSampling = enum(u8) {
    Single,
    Adaptive,
};

pub fn attenuation1(c: f32, distance: f32) f32 {
    return @exp(-distance * c);
}

pub fn attenuation3(c: Vec4f, distance: f32) Vec4f {
    return @exp(@splat(4, -distance) * c);
}

pub fn composeAlpha(radiance: Vec4f, throughput: Vec4f, transparent: bool) Vec4f {
    const alpha = if (transparent) std.math.max(1.0 - math.average3(throughput), 0.0) else 1.0;

    return .{ radiance[0], radiance[1], radiance[2], alpha };
}

pub fn powerHeuristic(f_pdf: f32, g_pdf: f32) f32 {
    const f2 = f_pdf * f_pdf;
    return f2 / (f2 + g_pdf * g_pdf);
}

// == power_heuristic(a, b) / a
pub fn predividedPowerHeuristic(f_pdf: f32, g_pdf: f32) f32 {
    return f_pdf / (f_pdf * f_pdf + g_pdf * g_pdf);
}

pub fn russianRoulette(throughput: *Vec4f, r: f32) bool {
    const continuation_probability = math.maxComponent3(throughput.*);

    if (r >= continuation_probability) {
        return true;
    }

    throughput.* /= @splat(4, continuation_probability);

    return false;
}
