const Renderstate = @import("../renderstate.zig").Renderstate;
const ts = @import("../../image/texture/sampler.zig");
const Texture = @import("../../image/texture/texture.zig").Texture;
const Scene = @import("../scene.zig").Scene;
const hlp = @import("sample_helper.zig");
pub usingnamespace hlp;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub inline fn sampleNormal(
    wo: Vec4f,
    rs: Renderstate,
    map: Texture,
    key: ts.Key,
    scene: *const Scene,
) Vec4f {
    return sampleNormalUV(wo, rs, rs.uv, map, key, scene);
}

pub inline fn sampleNormalUV(
    wo: Vec4f,
    rs: Renderstate,
    uv: Vec2f,
    map: Texture,
    key: ts.Key,
    scene: *const Scene,
) Vec4f {
    const nm = ts.sample2D_2(key, map, uv, scene);
    const nmz = @sqrt(std.math.max(1.0 - math.dot2(nm, nm), hlp.Dot_min));
    const n = math.normalize3(rs.tangentToWorld(.{ nm[0], nm[1], nmz, 0.0 }));

    // // Normal mapping can lead to normals facing away from the view direction.
    // // I believe the following is the (imperfect) workaround referred to as "flipping" by
    // // "Microfacet-based Normal Mapping for Robust Monte Carlo Path Tracing"
    // // https://drive.google.com/file/d/0BzvWIdpUpRx_ZHI1X2Z4czhqclk/view
    // if (math.dot3(n, wo) < 0.0) {
    //     return math.reflect3(rs.geo_n, n);
    // }

    // The above "flipping" is actually more complicated, and should also use wi instead of wo,
    // although I don't understand where wi should come from.
    _ = wo;

    return n;
}

pub inline fn nonSymmetryCompensation(wi: Vec4f, wo: Vec4f, geo_n: Vec4f, n: Vec4f) f32 {
    // Veach's compensation for "Non-symmetry due to shading normals".
    // See e.g. CorrectShadingNormal() at:
    // https://github.com/mmp/pbrt-v3/blob/master/src/integrators/bdpt.cpp#L55

    const numer = @fabs(math.dot3(wi, geo_n) * math.dot3(wo, n));
    const denom = std.math.max(@fabs(math.dot3(wi, n) * math.dot3(wo, geo_n)), hlp.Dot_min);

    return std.math.min(numer / denom, 8.0);
}
