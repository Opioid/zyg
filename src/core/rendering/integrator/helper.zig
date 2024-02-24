const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const LightSampling = enum(u8) {
    Single,
    Adaptive,
};

pub inline fn attenuation1(c: f32, distance: f32) f32 {
    return @exp(-distance * c);
}

pub inline fn attenuation3(c: Vec4f, distance: f32) Vec4f {
    return @exp(@as(Vec4f, @splat(-distance)) * c);
}

pub inline fn composeAlpha(radiance: Vec4f, throughput: Vec4f, transparent: bool) Vec4f {
    const alpha = if (transparent) math.max(1.0 - math.average3(throughput), 0.0) else 1.0;

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

pub inline fn russianRoulette(new_throughput: Vec4f, old_throughput: Vec4f, r: f32) ?f32 {
    const continuation_probability = @sqrt(math.max(math.hmax3(new_throughput) / math.hmax3(old_throughput), 0.0));

    if (r >= continuation_probability) {
        return null;
    }

    return continuation_probability;
}

pub fn nonSymmetryCompensation(wi: Vec4f, wo: Vec4f, geo_n: Vec4f, n: Vec4f) f32 {
    // Veach's compensation for "Non-symmetry due to shading normals".
    // See e.g. CorrectShadingNormal() at:
    // https://github.com/mmp/pbrt-v3/blob/master/src/integrators/bdpt.cpp#L55

    const numer = @abs(math.dot3(wi, geo_n) * math.dot3(wo, n));
    const denom = math.max(@abs(math.dot3(wi, n) * math.dot3(wo, geo_n)), math.safe.Dot_min);

    return numer / denom;
}
