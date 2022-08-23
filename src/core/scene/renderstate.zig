const Trafo = @import("composed_transformation.zig").ComposedTransformation;
const Filter = @import("../image/texture/sampler.zig").Filter;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Renderstate = struct {
    trafo: Trafo = undefined,

    p: Vec4f = undefined,
    geo_n: Vec4f = undefined,
    t: Vec4f = undefined,
    b: Vec4f = undefined,
    n: Vec4f = undefined,
    uv: Vec2f = undefined,

    prop: u32 = undefined,
    part: u32 = undefined,
    primitive: u32 = undefined,
    depth: u32 = undefined,

    time: u64 = undefined,

    filter: ?Filter = undefined,

    subsurface: bool = undefined,
    avoid_caustics: bool = undefined,

    pub inline fn tangentToWorld(self: *const Renderstate, v: Vec4f) Vec4f {
        return .{
            v[0] * self.t[0] + v[1] * self.b[0] + v[2] * self.n[0],
            v[0] * self.t[1] + v[1] * self.b[1] + v[2] * self.n[1],
            v[0] * self.t[2] + v[1] * self.b[2] + v[2] * self.n[2],
            0.0,
        };
    }

    pub inline fn ior(self: *const Renderstate) f32 {
        return self.p[3];
    }

    pub inline fn wavelength(self: *const Renderstate) f32 {
        return self.b[3];
    }
};
