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

    pub fn tangentToWorld3(self: Renderstate, v: Vec4f) Vec4f {
        return Vec4f.init3(
            v.v[0] * self.t.v[0] + v.v[1] * self.b.v[0] + v.v[2] * self.n.v[0],
            v.v[0] * self.t.v[1] + v.v[1] * self.b.v[1] + v.v[2] * self.n.v[1],
            v.v[0] * self.t.v[2] + v.v[1] * self.b.v[2] + v.v[2] * self.n.v[2],
        );
    }
};
