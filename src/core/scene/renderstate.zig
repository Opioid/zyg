const Trafo = @import("composed_transformation.zig").ComposedTransformation;
const ggx = @import("material/ggx.zig");
const Event = @import("shape/intersection.zig").Volume.Event;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const CausticsResolve = enum(u8) {
    Off,
    Rough,
    Full,
};

pub const Renderstate = struct {
    trafo: Trafo,

    p: Vec4f,
    geo_n: Vec4f,
    t: Vec4f,
    b: Vec4f,
    n: Vec4f,
    origin: Vec4f,
    uvw: Vec4f,

    ddx: Vec2f,
    ddy: Vec2f,

    ior: f32,
    wavelength: f32,
    min_alpha: f32,

    time: u64,

    prop: u32,
    part: u32,
    primitive: u32,
    volume_depth: u32,

    primary: bool,
    highest_priority: i8,
    event: Event,
    caustics: CausticsResolve,

    pub fn uv(self: Renderstate) Vec2f {
        const uvw = self.uvw;
        return .{ uvw[0], uvw[1] };
    }

    pub fn tangentToWorld(self: Renderstate, v: Vec4f) Vec4f {
        return .{
            v[0] * self.t[0] + v[1] * self.b[0] + v[2] * self.n[0],
            v[0] * self.t[1] + v[1] * self.b[1] + v[2] * self.n[1],
            v[0] * self.t[2] + v[1] * self.b[2] + v[2] * self.n[2],
            0.0,
        };
    }

    pub fn regularizeAlpha(self: Renderstate, alpha: Vec2f) Vec2f {
        // const mod_alpha = math.max2(alpha, @splat(self.min_alpha));

        // if (mod_alpha[0] <= ggx.Min_alpha and .Rough == self.caustics) {
        //     const l = math.length3(self.p - self.origin);
        //     const m = math.min(0.1 * (1.0 + l), 1.0);
        //     return math.max2(mod_alpha, @splat(m));
        // }

        // return mod_alpha;

        const mod_alpha = math.max2(alpha, @splat(self.min_alpha));

        if (alpha[0] <= ggx.MinAlpha) {
            if (.Rough == self.caustics) {
                const l = math.length3(self.p - self.origin);
                const m = math.min(0.1 * (1.0 + l), 1.0);
                return math.max2(mod_alpha, @splat(m));
            } else {
                return alpha;
            }
        }

        return mod_alpha;
    }

    pub fn volumeScatter(self: Renderstate) bool {
        return .Scatter == self.event;
    }

    pub fn exitSSS(self: Renderstate) bool {
        return .ExitSSS == self.event;
    }
};
