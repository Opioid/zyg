const base = @import("base");
usingnamespace base;
usingnamespace base.math;

pub fn interpolateP(a: Vec4f, b: Vec4f, c: Vec4f, u: f32, v: f32) Vec4f {
    const w = 1.0 - u - v;
    return a.mulScalar3(w).add3(b.mulScalar3(u)).add3(c.mulScalar3(v));
}
