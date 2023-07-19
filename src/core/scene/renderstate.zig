const Trafo = @import("composed_transformation.zig").ComposedTransformation;
const ggx = @import("material/ggx.zig");

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const CausticsResolve = enum(u8) {
    Off,
    Rough,
    Full,
};

pub const Renderstate = struct {
    trafo: Trafo = undefined,

    p: Vec4f = undefined,
    geo_n: Vec4f = undefined,
    t: Vec4f = undefined,
    b: Vec4f = undefined,
    n: Vec4f = undefined,

    ray_p: Vec4f = undefined,

    uv: Vec2f = undefined,

    prop: u32 = undefined,
    part: u32 = undefined,
    primitive: u32 = undefined,
    depth: u32 = undefined,

    time: u64 = undefined,

    subsurface: bool = undefined,
    caustics: CausticsResolve = undefined,

    pub fn tangentToWorld(self: Renderstate, v: Vec4f) Vec4f {
        return .{
            v[0] * self.t[0] + v[1] * self.b[0] + v[2] * self.n[0],
            v[0] * self.t[1] + v[1] * self.b[1] + v[2] * self.n[1],
            v[0] * self.t[2] + v[1] * self.b[2] + v[2] * self.n[2],
            0.0,
        };
    }

    pub fn ior(self: Renderstate) f32 {
        return self.p[3];
    }

    pub fn wavelength(self: Renderstate) f32 {
        return self.b[3];
    }

    pub fn regularizeAlpha(self: Renderstate, alpha: Vec2f) Vec2f {
        if (alpha[0] <= ggx.Min_alpha and .Rough == self.caustics) {
            const l = math.length3(self.p - self.ray_p);
            const m = math.min(0.1 * (1.0 + l), 1.0);
            return math.max2(alpha, @splat(2, m));
        }

        return alpha;
    }
};
