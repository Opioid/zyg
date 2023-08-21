const Trafo = @import("../composed_transformation.zig").ComposedTransformation;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Intersection = struct {
    trafo: Trafo,
    p: Vec4f,
    geo_n: Vec4f,
    t: Vec4f,
    b: Vec4f,
    n: Vec4f,
    uv: Vec2f,

    offset: f32,

    part: u32,
    primitive: u32,
};

pub const Interpolation = enum {
    Normal,
    All,
};

pub const Volume = struct {
    pub const Event = enum { Absorb, Scatter, Pass };

    li: Vec4f,
    tr: Vec4f,
    uvw: Vec4f = undefined,
    t: f32 = undefined,
    event: Event,

    pub fn initPass(w: Vec4f) Volume {
        return .{
            .li = @splat(0.0),
            .tr = w,
            .event = .Pass,
        };
    }
};
