const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const LightSampling = enum(u8) {
    Single,
    Adaptive,
};

pub inline fn attenuation1(c: f32, distance: f32) f32 {
    return @exp(-distance * c);
}

pub inline fn attenuation3(c: Vec4f, distance: f32) Vec4f {
    return @exp(@splat(4, -distance) * c);
}

pub inline fn composeAlpha(radiance: Vec4f, throughput: Vec4f, transparent: bool) Vec4f {
    const alpha = if (transparent) std.math.max(1.0 - math.average3(throughput), 0.0) else 1.0;

    return .{ radiance[0], radiance[1], radiance[2], alpha };
}

pub inline fn powerHeuristic(f_pdf: f32, g_pdf: f32) f32 {
    const f2 = f_pdf * f_pdf;
    return f2 / (f2 + g_pdf * g_pdf);
}

// == power_heuristic(a, b) / a
pub inline fn predividedPowerHeuristic(f_pdf: f32, g_pdf: f32) f32 {
    return f_pdf / (f_pdf * f_pdf + g_pdf * g_pdf);
}

pub inline fn russianRoulette(new_throughput: *Vec4f, old_throughput: Vec4f, r: f32) bool {
    const continuation_probability = @sqrt(std.math.max(math.hmax3(new_throughput.*) / math.hmax3(old_throughput), 0.0));

    if (r >= continuation_probability) {
        return true;
    }

    new_throughput.* /= @splat(4, continuation_probability);

    return false;
}
