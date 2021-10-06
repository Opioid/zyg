const Filter = @import("../image/texture/sampler.zig").Filter;
const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Renderstate = struct {
    p: Vec4f = undefined,
    geo_n: Vec4f = undefined,
    t: Vec4f = undefined,
    b: Vec4f = undefined,
    n: Vec4f = undefined,
    uv: Vec2f = undefined,

    prop: u32 = undefined,
    part: u32 = undefined,
    primitive: u32 = undefined,

    filter: ?Filter = undefined,

    pub fn tangentToWorld3(self: Renderstate, v: Vec4f) Vec4f {
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
};
