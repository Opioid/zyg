const Renderstate = @import("../renderstate.zig").Renderstate;
const bxdf = @import("bxdf.zig");

const base = @import("base");
const math = base.math;
const Frame = math.Frame;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Base = struct {
    pub const Properties = packed struct {
        translucent: bool = false,
        can_evaluate: bool = false,
        avoid_caustics: bool = false,
        volumetric: bool = false,
        flakes: bool = false,
        exit_sss: bool = false,
        lower_priority: bool = false,
    };

    frame: Frame,

    geo_n: Vec4f,
    n: Vec4f,
    wo: Vec4f,
    albedo: Vec4f,

    alpha: Vec2f,

    thickness: f32,

    properties: Properties,

    const Self = @This();

    pub fn init(rs: Renderstate, wo: Vec4f, albedo: Vec4f, alpha: Vec2f, thickness: f32, priority: i8) Self {
        return .{
            .frame = undefined,
            .geo_n = rs.geo_n,
            .n = rs.n,
            .wo = wo,
            .albedo = albedo,
            .alpha = alpha,
            .thickness = thickness,
            .properties = .{
                .can_evaluate = true,
                .avoid_caustics = .Full != rs.caustics,
                .lower_priority = priority < rs.highest_priority,
            },
        };
    }

    pub fn initTBN(rs: Renderstate, wo: Vec4f, albedo: Vec4f, alpha: Vec2f, thickness: f32, priority: i8, can_evaluate: bool) Self {
        return .{
            .frame = .{ .x = rs.t, .y = rs.b, .z = rs.n },
            .geo_n = rs.geo_n,
            .n = rs.n,
            .wo = wo,
            .albedo = albedo,
            .alpha = alpha,
            .thickness = thickness,
            .properties = .{
                .can_evaluate = can_evaluate,
                .avoid_caustics = .Full != rs.caustics,
                .lower_priority = priority < rs.highest_priority,
            },
        };
    }

    pub fn geometricNormal(self: Self) Vec4f {
        return self.geo_n;
    }

    pub fn interpolatedNormal(self: Self) Vec4f {
        return self.n;
    }

    pub fn shadingNormal(self: Self) Vec4f {
        return self.frame.z;
    }

    pub fn shadingTangent(self: Self) Vec4f {
        return self.frame.x;
    }

    pub fn shadingBitangent(self: Self) Vec4f {
        return self.frame.y;
    }

    pub fn sameHemisphere(self: Self, v: Vec4f) bool {
        return math.dot3(self.geo_n, v) > 0.0;
    }

    pub fn avoidCaustics(self: Self) bool {
        return self.properties.avoid_caustics;
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
