const Renderstate = @import("../renderstate.zig").Renderstate;
const ts = @import("../../image/texture/texture_sampler.zig");
const Texture = @import("../../image/texture/texture.zig").Texture;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Scene = @import("../scene.zig").Scene;
const hlp = @import("sample_helper.zig");
pub usingnamespace hlp;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub fn sampleNormal(wo: Vec4f, rs: Renderstate, map: Texture, key: ts.Key, sampler: *Sampler, scene: *const Scene) Vec4f {
    // Reconstruct normal from normal texture
    const nm = ts.sample2D_2(key, map, rs.uv, sampler, scene);
    const nmz = @sqrt(math.max(1.0 - math.dot2(nm, nm), 0.01));
    const n = math.normalize3(rs.tangentToWorld(.{ nm[0], nm[1], nmz, 0.0 }));

    // Normal mapping can lead to normals facing away from the view direction.
    // Use something similar to iray shading normal adaption
    // This particular implementation is from:
    // https://github.com/kennyalive/YAR/blob/8068aeec1e9df298f9703017f99fe8e046aab94d/src/reference/shading_context.cpp

    const ng = rs.geo_n;
    const r = math.reflect3(n, wo);
    const a = math.dot3(ng, r);
    if (a >= 0.0) {
        return n;
    }

    // For almost tangential 'wo' we have catastrophic cancellation in 'wo + tangent' expression below.
    // For this configuration we know that the result will be close to geometric normal, so return it directly.
    const cos_threshold = 0.0017453; // cos(89.9 degrees)
    if (math.dot3(ng, wo) < cos_threshold) {
        return ng;
    }

    const b = math.dot3(ng, n);

    const epsilon = @as(f32, 1e-4);

    var tangent: Vec4f = undefined;
    if (b > epsilon) {
        const distance_to_surface_along_normal = @fabs(a) / b;
        tangent = math.normalize3(r + @splat(4, distance_to_surface_along_normal) * n);
    } else {
        // For small 'b' (especially when it's zero) it's numerically challenging to compute 'tangent' as we do above.
        // For this configuration shading normal is almost tangential, so use it as a tangent vector.
        tangent = n;
    }

    tangent += @splat(4, epsilon) * ng;

    return math.normalize3(wo + tangent);
}

pub fn nonSymmetryCompensation(wi: Vec4f, wo: Vec4f, geo_n: Vec4f, n: Vec4f) f32 {
    // Veach's compensation for "Non-symmetry due to shading normals".
    // See e.g. CorrectShadingNormal() at:
    // https://github.com/mmp/pbrt-v3/blob/master/src/integrators/bdpt.cpp#L55

    const numer = @fabs(math.dot3(wi, geo_n) * math.dot3(wo, n));
    const denom = math.max(@fabs(math.dot3(wi, n) * math.dot3(wo, geo_n)), hlp.Dot_min);

    return numer / denom;
}

pub fn triplanarMapping(p: Vec4f, n: Vec4f) Vec2f {
    const an = @fabs(n);
    if (an[0] > an[1] and an[0] > an[2]) {
        const sign = std.math.copysign(@as(f32, 1.0), p[0]);
        return .{ math.frac(sign * p[1] + 0.5), math.frac(p[2] + 0.5) };
    } else if (an[1] > an[0] and an[1] > an[2]) {
        const sign = std.math.copysign(@as(f32, 1.0), p[1]);
        return .{ math.frac(-sign * p[0] + 0.5), math.frac(p[2] + 0.5) };
    } else {
        const sign = std.math.copysign(@as(f32, 1.0), p[2]);
        return .{ math.frac(sign * p[0] + 0.5), math.frac(p[1] + 0.5) };
    }
}
