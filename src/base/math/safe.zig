const math = @import("vector4.zig");
const Vec4f = math.Vec4f;
const util = @import("util.zig");

pub const DotMin: f32 = 0.00001;

pub inline fn absDotC(a: Vec4f, b: Vec4f, c: bool) f32 {
    const d = math.dot3(a, b);
    return if (c) @abs(d) else d;
}

pub inline fn clamp(x: f32) f32 {
    return util.clamp(x, DotMin, 1.0);
}

pub inline fn clampAbs(x: f32) f32 {
    return util.clamp(@abs(x), DotMin, 1.0);
}

pub inline fn clampDot(a: Vec4f, b: Vec4f) f32 {
    return util.clamp(math.dot3(a, b), DotMin, 1.0);
}

pub inline fn clampAbsDot(a: Vec4f, b: Vec4f) f32 {
    return util.clamp(@abs(math.dot3(a, b)), DotMin, 1.0);
}
