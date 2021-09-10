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
    scene: *const Scene,
) Vec4f {
    return sampleNormalUV(wo, rs, rs.uv, map, scene);
}

pub fn sampleNormalUV(
    wo: Vec4f,
    rs: Renderstate,
    uv: Vec2f,
    map: Texture,
    scene: *const Scene,
) Vec4f {
    const nm = ts.sample2D_2(map, uv, scene);
    const nmz = @sqrt(std.math.max(1.0 - nm.dot(nm), hlp.Dot_min));
    const n = rs.tangentToWorld3(Vec4f.init3(nm.v[0], nm.v[1], nmz));

    // Normal mapping can lead to normals facing away from the view direction.
    // I believe the following is the (imperfect) workaround referred to as "flipping" by
    // "Microfacet-based Normal Mapping for Robust Monte Carlo Path Tracing"
    // https://drive.google.com/file/d/0BzvWIdpUpRx_ZHI1X2Z4czhqclk/view
    if (n.dot3(wo) < 0.0) {
        return rs.geo_n.reflect3(n);
    }

    return n;
}
