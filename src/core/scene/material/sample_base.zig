const Renderstate = @import("../renderstate.zig").Renderstate;
const hlp = @import("sample_helper.zig");
const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Layer = struct {
    t: Vec4f,
    b: Vec4f,
    n: Vec4f,

    pub fn tangentToWorld(self: Layer, v: Vec4f) Vec4f {
        return .{
            v[0] * self.t[0] + v[1] * self.b[0] + v[2] * self.n[0],
            v[0] * self.t[1] + v[1] * self.b[1] + v[2] * self.n[1],
            v[0] * self.t[2] + v[1] * self.b[2] + v[2] * self.n[2],
            0.0,
        };
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
        const tb = math.orthonormalBasis3(shading_n);

        return .{
            .layer = .{ .t = tb[0], .b = tb[1], .n = shading_n },
            .geo_n = rs.geo_n,
            .n = rs.n,
            .wo = wo,
            .albedo = albedo,
            .radiance = radiance,
        };
    }

    pub fn geometricNormal(self: Self) Vec4f {
        return self.geo_n;
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
        return math.dot3(self.geo_n, v) > 0.0;
    }
};
