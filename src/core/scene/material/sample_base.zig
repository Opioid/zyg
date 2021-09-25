const Renderstate = @import("../renderstate.zig").Renderstate;
const hlp = @import("sample_helper.zig");
const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Flags = base.flags.Flags;

pub const Layer = struct {
    t: Vec4f,
    b: Vec4f,
    n: Vec4f,

    pub fn tangentToWorld(self: Layer, v: Vec4f) Vec4f {
        // return .{
        //     v[0] * self.t[0] + v[1] * self.b[0] + v[2] * self.n[0],
        //     v[0] * self.t[1] + v[1] * self.b[1] + v[2] * self.n[1],
        //     v[0] * self.t[2] + v[1] * self.b[2] + v[2] * self.n[2],
        //     0.0,
        // };

        var result = @shuffle(f32, v, v, [4]i32{ 0, 0, 0, 0 });
        result = result * self.t;
        var temp = @shuffle(f32, v, v, [4]i32{ 1, 1, 1, 1 });
        temp = temp * self.b;
        result = result + temp;
        temp = @shuffle(f32, v, v, [4]i32{ 2, 2, 2, 2 });
        temp = temp * self.n;
        return result + temp;
    }

    pub fn worldToTangent(self: Layer, v: Vec4f) Vec4f {
        return .{
            v[0] * self.t[0] + v[1] * self.t[1] + v[2] * self.t[2],
            v[0] * self.b[0] + v[1] * self.b[1] + v[2] * self.b[2],
            v[0] * self.n[0] + v[1] * self.n[1] + v[2] * self.n[2],
            0.0,
        };
    }

    pub fn clampNdot(self: Layer, v: Vec4f) f32 {
        return hlp.clampDot(self.n, v);
    }

    pub fn clampAbsNdot(self: Layer, v: Vec4f) f32 {
        return hlp.clampAbsDot(self.n, v);
    }

    pub fn setTangentFrame(self: *Layer, t: Vec4f, b: Vec4f, n: Vec4f) void {
        self.t = t;
        self.b = b;
        self.n = n;
    }

    pub fn rotateTangenFrame(self: *Layer, a: f32) void {
        const t = self.t;
        const b = self.b;

        const sin_a = @splat(4, @sin(a));
        const cos_a = @splat(4, @cos(a));

        self.t = cos_a * t + sin_a * b;
        self.b = -sin_a * t + cos_a * b;
    }
};

pub const SampleBase = struct {
    pub const Property = enum(u32) {
        None = 0,
        Pure_emissive = 1 << 0,
        Translucent = 1 << 1,
        Can_evaluate = 1 << 2,
        Avoid_caustics = 1 << 3,
    };

    layer: Layer = undefined,

    geo_n: Vec4f,
    n: Vec4f,
    wo: Vec4f,
    albedo: Vec4f,
    radiance: Vec4f,

    alpha: Vec2f,

    properties: Flags(Property),

    const Self = @This();

    pub fn init(
        rs: Renderstate,
        wo: Vec4f,
        albedo: Vec4f,
        radiance: Vec4f,
        alpha: Vec2f,
    ) SampleBase {
        return .{
            .geo_n = rs.geo_n,
            .n = rs.n,
            .wo = wo,
            .albedo = albedo,
            .radiance = radiance,
            .alpha = alpha,
            .properties = Flags(Property).init1(.Can_evaluate),
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
