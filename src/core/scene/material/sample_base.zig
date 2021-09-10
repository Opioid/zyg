const Renderstate = @import("../renderstate.zig").Renderstate;
const hlp = @import("sample_helper.zig");
const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Layer = struct {
    t: Vec4f,
    b: Vec4f,
    n: Vec4f,

    pub fn tangentToWorld(self: Layer, v: Vec4f) Vec4f {
        return Vec4f.init3(
            v.v[0] * self.t.v[0] + v.v[1] * self.b.v[0] + v.v[2] * self.n.v[0],
            v.v[0] * self.t.v[1] + v.v[1] * self.b.v[1] + v.v[2] * self.n.v[1],
            v.v[0] * self.t.v[2] + v.v[1] * self.b.v[2] + v.v[2] * self.n.v[2],
        );
    }

    pub fn clampNdot(self: Layer, v: Vec4f) f32 {
        return hlp.clampDot(self.n, v);
    }
};

pub const SampleBase = struct {
    layer: Layer,

    geo_n: Vec4f,
    n: Vec4f,
    wo: Vec4f,
    albedo: Vec4f,
    radiance: Vec4f,

    const Self = @This();

    pub fn init(rs: Renderstate, wo: Vec4f, albedo: Vec4f, radiance: Vec4f) SampleBase {
        return .{
            .layer = .{ .t = rs.t, .b = rs.b, .n = rs.n },
            .geo_n = rs.geo_n,
            .n = rs.n,
            .wo = wo,
            .albedo = albedo,
            .radiance = radiance,
        };
    }

    pub fn initN(rs: Renderstate, shading_n: Vec4f, wo: Vec4f, albedo: Vec4f, radiance: Vec4f) SampleBase {
        const tb = Vec4f.orthonormalBasis3(shading_n);

        return .{
            .layer = .{ .t = tb[0], .b = tb[1], .n = shading_n },
            .geo_n = rs.geo_n,
            .n = rs.n,
            .wo = wo,
            .albedo = albedo,
            .radiance = radiance,
        };
    }

    pub fn shadingNormal(self: Self) Vec4f {
        return self.layer.n;
    }

    pub fn shadingTangent(self: Self) Vec4f {
        return self.layer.t;
    }

    pub fn shadingBitangent(self: Self) Vec4f {
        return self.layer.b;
    }

    pub fn sameHemisphere(self: Self, v: Vec4f) bool {
        return self.geo_n.dot3(v) > 0.0;
    }
};
