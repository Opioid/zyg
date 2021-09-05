const Renderstate = @import("../renderstate.zig").Renderstate;
const base = @import("base");
usingnamespace base.math;

pub const Layer = struct {
    t: Vec4f,
    b: Vec4f,
    n: Vec4f,
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
