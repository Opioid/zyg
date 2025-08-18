const Trafo = @import("composed_transformation.zig").ComposedTransformation;
const ggx = @import("material/ggx.zig");
const hlp = @import("material/material_helper.zig");
const Event = @import("shape/intersection.zig").Volume.Event;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Renderstate = struct {
    trafo: Trafo,

    p: Vec4f,
    geo_n: Vec4f,
    t: Vec4f,
    b: Vec4f,
    n: Vec4f,
    origin: Vec4f,
    uvw: Vec4f,

    time: u64,

    stochastic_r: f32,
    ior: f32,
    wavelength: f32,
    reg_weight: f32,
    reg_alpha: f32,

    prop: u32,
    part: u32,
    primitive: u32,
    volume_depth: u32,

    primary: bool,
    highest_priority: i8,
    event: Event,
    caustics: bool,

    pub fn uv(self: Renderstate) Vec2f {
        const uvw = self.uvw;
        return .{ uvw[0], uvw[1] };
    }

    pub fn triplanarSt(self: Renderstate) Vec2f {
        const op = self.trafo.worldToObjectPoint(self.p);
        const on = self.trafo.worldToObjectNormal(self.geo_n);

        return hlp.triplanarMapping(op, on);
    }

    pub fn tangentToWorld(self: Renderstate, v: Vec4f) Vec4f {
        return .{
            v[0] * self.t[0] + v[1] * self.b[0] + v[2] * self.n[0],
            v[0] * self.t[1] + v[1] * self.b[1] + v[2] * self.n[1],
            v[0] * self.t[2] + v[1] * self.b[2] + v[2] * self.n[2],
            0.0,
        };
    }

    pub fn regularizeAlpha(self: Renderstate, alpha: Vec2f, specular_threshold: f32) Vec2f {
        const weight = self.reg_weight;

        if (0.0 == weight or (alpha[0] <= specular_threshold and !self.caustics)) {
            return alpha;
        }

        const one: Vec2f = @splat(1.0);
        return one - ((one - alpha) * @as(Vec2f, @splat(1.0 - weight * self.reg_alpha)));
    }

    pub fn volumeScatter(self: Renderstate) bool {
        return .Scatter == self.event;
    }

    pub fn exitSSS(self: Renderstate) bool {
        return .ExitSSS == self.event;
    }
};
