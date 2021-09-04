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

    const Self = @This();

    pub fn init(rs: Renderstate, wo: Vec4f) SampleBase {
        return .{
            .layer = .{ .t = rs.t, .b = rs.b, .n = rs.n },
            .geo_n = rs.geo_n,
            .n = rs.n,
            .wo = wo,
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
};
