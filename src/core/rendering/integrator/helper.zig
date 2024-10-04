const Probe = @import("../../scene/vertex.zig").Vertex.Probe;

const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Depth = struct {
    surface: u16,
    volume: u16,
};

pub const LightSampling = struct {
    split_threshold: f32,

    pub fn splitThreshold(self: LightSampling, depth: Probe.Depth, offset: u32) f32 {
        const total_depth = depth.surface + depth.volume - offset;

        // 0.01^4 = 0.00000001

        const threshold = self.split_threshold;

        const low_threshold: f32 = 0.00000001;

        return math.min(if (total_depth < 4) threshold else low_threshold, threshold);
    }
};

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

pub inline fn russianRoulette(throughput: *Vec4f, r: f32) bool {
    const max = math.hmax3(throughput.*);

    const continuation_probability = max / 0.1;

    if (continuation_probability < 1.0) {
        if (r >= continuation_probability) {
            return true;
        }

        throughput.* /= @splat(continuation_probability);
    }

    return false;
}

pub fn nonSymmetryCompensation(wi: Vec4f, wo: Vec4f, geo_n: Vec4f, n: Vec4f) f32 {
    // Veach's compensation for "Non-symmetry due to shading normals".
    // See e.g. CorrectShadingNormal() at:
    // https://github.com/mmp/pbrt-v3/blob/master/src/integrators/bdpt.cpp#L55

    const numer = @abs(math.dot3(wi, geo_n) * math.dot3(wo, n));
    const denom = math.max(@abs(math.dot3(wi, n) * math.dot3(wo, geo_n)), math.safe.Dot_min);

    return numer / denom;
}
