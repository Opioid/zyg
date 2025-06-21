const Renderstate = @import("../renderstate.zig").Renderstate;
const ts = @import("../../texture/texture_sampler.zig");
const Texture = @import("../../texture/texture.zig").Texture;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Context = @import("../context.zig").Context;
const DifferentialSurface = @import("../shape/intersection.zig").DifferentialSurface;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Frame = math.Frame;

const std = @import("std");

fn gramSchmidt(v: Vec4f, w: Vec4f) Vec4f {
    return v - @as(Vec4f, @splat(math.dot3(v, w))) * w;
}

pub fn sampleNormal(wo: Vec4f, rs: Renderstate, map: Texture, sampler: *Sampler, context: Context) Vec4f {
    // Reconstruct normal from normal texture
    const nmxy = ts.sample2D_2(map, rs, sampler, context);
    const nmz = @sqrt(math.max(1.0 - math.dot2(nmxy, nmxy), 0.01));
    const nm = Vec4f{ nmxy[0], nmxy[1], nmz, 0.0 };

    var n: Vec4f = undefined;

    if (.ObjectPos == map.mode.tex_coord) {
        const t, const b = math.orthonormalBasis3(rs.n);

        const frame: Frame = .{ .x = t, .y = b, .z = rs.n };

        n = math.normalize3(frame.frameToWorld(nm));
    } else if (.Triplanar == map.mode.tex_coord) {
        const wt = triplanarTangent(rs.n, rs.trafo);

        const bt = math.cross3(rs.n, wt);
        const nt = math.cross3(bt, rs.n);

        const frame: Frame = .{ .x = nt, .y = bt, .z = rs.n };

        n = math.normalize3(frame.frameToWorld(nm));
    } else {
        n = math.normalize3(rs.tangentToWorld(nm));
    }

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

    const epsilon = 1e-4;

    var tangent: Vec4f = undefined;
    if (b > epsilon) {
        const distance_to_surface_along_normal = @abs(a) / b;
        tangent = math.normalize3(r + @as(Vec4f, @splat(distance_to_surface_along_normal)) * n);
    } else {
        // For small 'b' (especially when it's zero) it's numerically challenging to compute 'tangent' as we do above.
        // For this configuration shading normal is almost tangential, so use it as a tangent vector.
        tangent = n;
    }

    tangent += @as(Vec4f, @splat(epsilon)) * ng;

    return math.normalize3(wo + tangent);
}

// p and n should be in object space
pub fn triplanarMapping(p: Vec4f, n: Vec4f) Vec2f {
    const an = @abs(n);
    if (an[0] > an[1] and an[0] > an[2]) {
        const sign = std.math.copysign(@as(f32, 1.0), n[0]);
        return .{ sign * p[2] + 0.5, -p[1] + 0.5 };
    } else if (an[1] > an[0] and an[1] > an[2]) {
        const sign = std.math.copysign(@as(f32, 1.0), n[1]);
        return .{ sign * p[0] + 0.5, -p[2] + 0.5 };
    } else {
        const sign = std.math.copysign(@as(f32, 1.0), n[2]);
        return .{ -sign * p[0] + 0.5, -p[1] + 0.5 };
    }
}

pub fn triplanarDifferential(wn: Vec4f, trafo: Trafo) DifferentialSurface {
    const n = trafo.worldToObjectNormal(wn);

    const an = @abs(n);
    if (an[0] > an[1] and an[0] > an[2]) {
        const sign = std.math.copysign(@as(f32, 1.0), n[0]);

        return .{
            .dpdu = @as(Vec4f, @splat(sign * trafo.scaleZ())) * trafo.rotation.r[2],
            .dpdv = @as(Vec4f, @splat(-1.0 * trafo.scaleY())) * @abs(trafo.rotation.r[1]),
        };
    } else if (an[1] > an[0] and an[1] > an[2]) {
        const sign = std.math.copysign(@as(f32, 1.0), n[1]);

        return .{
            .dpdu = @as(Vec4f, @splat(sign * trafo.scaleX())) * trafo.rotation.r[0],
            .dpdv = @as(Vec4f, @splat(-1.0 * trafo.scaleZ())) * @abs(trafo.rotation.r[2]),
        };
    } else {
        const sign = std.math.copysign(@as(f32, 1.0), n[2]);

        return .{
            .dpdu = @as(Vec4f, @splat(-sign * trafo.scaleX())) * trafo.rotation.r[0],
            .dpdv = @as(Vec4f, @splat(-1.0 * trafo.scaleY())) * @abs(trafo.rotation.r[1]),
        };
    }
}

// n should be in world space
pub fn triplanarTangent(wn: Vec4f, trafo: Trafo) Vec4f {
    const n = trafo.worldToObjectNormal(wn);

    const an = @abs(n);
    if (an[0] > an[1] and an[0] > an[2]) {
        const sign = std.math.copysign(@as(f32, 1.0), n[0]);
        return @as(Vec4f, @splat(sign)) * trafo.rotation.r[2];
    } else if (an[1] > an[0] and an[1] > an[2]) {
        const sign = std.math.copysign(@as(f32, 1.0), n[1]);
        return @as(Vec4f, @splat(sign)) * trafo.rotation.r[0];
    } else {
        const sign = std.math.copysign(@as(f32, 1.0), n[2]);
        return @as(Vec4f, @splat(-sign)) * trafo.rotation.r[0];
    }
}
