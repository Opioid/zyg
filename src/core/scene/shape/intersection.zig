const Trafo = @import("../composed_transformation.zig").ComposedTransformation;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Intersection = struct {
    trafo: Trafo = undefined,
    p: Vec4f = undefined,
    geo_n: Vec4f = undefined,
    t: Vec4f = undefined,
    b: Vec4f = undefined,
    n: Vec4f = undefined,
    uv: Vec2f = undefined,

    part: u32 = undefined,
    primitive: u32 = undefined,
};

pub const Interpolation = enum {
    All,
    NoTangentSpace,
    Normal,
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
            .li = @splat(4, @as(f32, 0.0)),
            .tr = w,
            .event = .Pass,
        };
    }
};
