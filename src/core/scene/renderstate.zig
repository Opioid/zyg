const base = @import("base");
usingnamespace base.math;

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
};
