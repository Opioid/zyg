const Renderstate = @import("../renderstate.zig").Renderstate;
const ts = @import("../../image/texture/sampler.zig");
const Texture = @import("../../image/texture/texture.zig").Texture;
const Scene = @import("../scene.zig").Scene;
const hlp = @import("sample_helper.zig");
const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub fn sampleNormal(
    wo: Vec4f,
    rs: Renderstate,
    map: Texture,
    key: ts.Key,
    scene: Scene,
) Vec4f {
    return sampleNormalUV(wo, rs, rs.uv, map, key, scene);
}

pub fn sampleNormalUV(
    wo: Vec4f,
    rs: Renderstate,
    uv: Vec2f,
    map: Texture,
    key: ts.Key,
    scene: Scene,
) Vec4f {
    const nm = ts.sample2D_2(key, map, uv, scene);
    const nmz = @sqrt(std.math.max(1.0 - math.dot2(nm, nm), hlp.Dot_min));
    const n = math.normalize3(rs.tangentToWorld3(.{ nm[0], nm[1], nmz, 0.0 }));

    // Normal mapping can lead to normals facing away from the view direction.
    // I believe the following is the (imperfect) workaround referred to as "flipping" by
    // "Microfacet-based Normal Mapping for Robust Monte Carlo Path Tracing"
    // https://drive.google.com/file/d/0BzvWIdpUpRx_ZHI1X2Z4czhqclk/view
    if (math.dot3(n, wo) < 0.0) {
        return math.reflect3(rs.geo_n, n);
    }

    return n;
}
