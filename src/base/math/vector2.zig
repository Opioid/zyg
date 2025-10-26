const math = @import("util.zig");

pub const Vec2b = @Vector(2, u8);
pub const Vec2us = @Vector(2, u16);
pub const Vec2i = @Vector(2, i32);
pub const Vec2u = @Vector(2, u32);
pub const Vec2f = @Vector(2, f32);
pub const Vec2ul = @Vector(2, u64);

const builtin = @import("builtin");

pub inline fn dot2(a: Vec2f, b: Vec2f) f32 {
    return a[0] * b[0] + a[1] * b[1];
}

pub inline fn squaredLength2(v: Vec2f) f32 {
    return dot2(v, v);
}

pub inline fn length2(v: Vec2f) f32 {
    return @sqrt(dot2(v, v));
}

pub inline fn normalize2(v: Vec2f) Vec2f {
    const i = @sqrt(1.0 / dot2(v, v));
    return @as(Vec2f, @splat(i)) * v;
}

pub inline fn min2(a: Vec2f, b: Vec2f) Vec2f {
    return switch (builtin.target.cpu.arch) {
        .aarch64, .aarch64_be => @min(a, b),
        inline else => .{
            math.min(a[0], b[0]),
            math.min(a[1], b[1]),
        },
    };
}

pub inline fn max2(a: Vec2f, b: Vec2f) Vec2f {
    return switch (builtin.target.cpu.arch) {
        .aarch64, .aarch64_be => @max(a, b),
        inline else => .{
            math.max(a[0], b[0]),
            math.max(a[1], b[1]),
        },
    };
}

pub inline fn clamp2(v: Vec2f, mi: Vec2f, ma: Vec2f) Vec2f {
    return min2(max2(v, mi), ma);
}
