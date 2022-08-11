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
