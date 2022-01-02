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

    pub fn swapped(self: Layer, same_side: bool) Layer {
        if (same_side) {
            return self;
        }

        return .{ .t = self.t, .b = self.b, .n = -self.n };
    }

    pub fn tangentToWorld(self: Layer, v: Vec4f) Vec4f {
        // return .{
        //     v[0] * self.t[0] + v[1] * self.b[0] + v[2] * self.n[0],
        //     v[0] * self.t[1] + v[1] * self.b[1] + v[2] * self.n[1],
        //     v[0] * self.t[2] + v[1] * self.b[2] + v[2] * self.n[2],
        //     0.0,
        // };

        var result = @splat(4, v[0]); // @shuffle(f32, v, v, [4]i32{ 0, 0, 0, 0 });
        result = result * self.t;
        var temp = @splat(4, v[1]); // @shuffle(f32, v, v, [4]i32{ 1, 1, 1, 1 });
        temp = temp * self.b;
        result = result + temp;
        temp = @splat(4, v[2]); // @shuffle(f32, v, v, [4]i32{ 2, 2, 2, 2 });
        temp = temp * self.n;
        return result + temp;
    }

    pub fn worldToTangent(self: Layer, v: Vec4f) Vec4f {
        const t = v * self.t;
        const b = v * self.b;
        const n = v * self.n;

        return .{
            t[0] + t[1] + t[2],
            b[0] + b[1] + b[2],
            n[0] + n[1] + n[2],
            0.0,
        };
    }

    pub fn nDot(self: Layer, v: Vec4f) f32 {
        return math.dot3(self.n, v);
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

    pub fn setNormal(self: *Layer, n: Vec4f) void {
        const tb = math.orthonormalBasis3(n);
        self.t = tb[0];
        self.b = tb[1];
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
        CanEvaluate = 1 << 2,
        AvoidCaustics = 1 << 3,
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
            .properties = Flags(Property).init2(.CanEvaluate, .AvoidCaustics, rs.avoid_caustics),
        };
    }

    pub fn initN(wo: Vec4f, geo_n: Vec4f, n: Vec4f, alpha: f32) SampleBase {
        return .{
            .geo_n = geo_n,
            .n = n,
            .wo = wo,
            .albedo = @splat(4, @as(f32, 0.0)),
            .radiance = @splat(4, @as(f32, 0.0)),
            .alpha = @splat(2, alpha),
            .properties = .{},
        };
    }

    pub fn geometricNormal(self: Self) Vec4f {
        return self.geo_n;
    }

    pub fn interpolatedNormal(self: Self) Vec4f {
        return self.n;
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

    pub fn avoidCaustics(self: Self) bool {
        return self.properties.is(.AvoidCaustics);
    }
};

pub const IoR = struct {
    eta_t: f32,
    eta_i: f32,

    pub fn swapped(self: IoR, same_side: bool) IoR {
        if (same_side) {
            return self;
        }

        return .{ .eta_t = self.eta_i, .eta_i = self.eta_t };
    }
};
