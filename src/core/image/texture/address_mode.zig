const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Mode = union(enum) {
    Clamp,
    Repeat,

    pub fn f(m: Mode, x: f32) f32 {
        return switch (m) {
            .Clamp => Clamp.f(x),
            .Repeat => Repeat.f(x),
        };
    }

    pub fn f3(m: Mode, x: Vec4f) Vec4f {
        return switch (m) {
            .Clamp => Clamp.f3(x),
            .Repeat => Repeat.f3(x),
        };
    }

    pub fn increment(m: Mode, v: i32, max: i32) i32 {
        return switch (m) {
            .Clamp => Clamp.increment(v, max),
            .Repeat => Repeat.increment(v, max),
        };
    }

    pub fn increment3(m: Mode, v: Vec4i, max: Vec4i) Vec4i {
        return switch (m) {
            .Clamp => Clamp.increment3(v, max),
            .Repeat => .{
                Repeat.increment(v[0], max[0]),
                Repeat.increment(v[1], max[1]),
                Repeat.increment(v[2], max[2]),
                0,
            },
        };
    }

    pub fn lowerBound(m: Mode, v: i32, max: i32) i32 {
        return switch (m) {
            .Clamp => Clamp.lowerBound(v),
            .Repeat => Repeat.lowerBound(v, max),
        };
    }

    pub fn lowerBound3(m: Mode, v: Vec4i, max: Vec4i) Vec4i {
        return switch (m) {
            .Clamp => Clamp.lowerBound3(v),
            .Repeat => .{
                Repeat.lowerBound(v[0], max[0]),
                Repeat.lowerBound(v[1], max[1]),
                Repeat.lowerBound(v[2], max[2]),
                0,
            },
        };
    }

    pub fn offset(m: Mode, v: i32, d: i32, max: i32) i32 {
        return switch (m) {
            .Clamp => Clamp.offset(v, d, max),
            .Repeat => Repeat.offset(v, d, max),
        };
    }

    pub fn offset2(m: Mode, v: Vec2i, d: Vec2i, max: Vec2i) Vec2i {
        return switch (m) {
            .Clamp => Clamp.offset2(v, d, max),
            .Repeat => .{ Repeat.offset(v[0], d[0], max[0]), Repeat.offset(v[1], d[1], max[1]) },
        };
    }

    pub fn offset3(m: Mode, v: Vec4i, d: Vec4i, max: Vec4i) Vec4i {
        return switch (m) {
            .Clamp => Clamp.offset3(v, d, max),
            .Repeat => .{
                Repeat.offset(v[0], d[0], max[0]),
                Repeat.offset(v[1], d[1], max[1]),
                Repeat.offset(v[2], d[2], max[2]),
                0,
            },
        };
    }
};

pub const Clamp = struct {
    pub fn f(x: f32) f32 {
        return std.math.clamp(x, 0.0, 1.0);
    }

    pub fn f3(x: Vec4f) Vec4f {
        return math.clamp(x, 0.0, 1.0);
    }

    pub fn increment(v: i32, max: i32) i32 {
        return @min(v + 1, max);
    }

    pub fn increment3(v: Vec4i, max: Vec4i) Vec4i {
        return @min(v + Vec4i{ 1, 1, 1, 0 }, max);
    }

    pub fn lowerBound(v: i32) i32 {
        return @max(v, 0);
    }

    pub fn lowerBound3(v: Vec4i) Vec4i {
        return @max(v, @splat(4, @as(i32, 0)));
    }

    pub fn offset(v: i32, d: i32, max: i32) i32 {
        const x = v + d;
        return @max(@min(x, max), 0);
    }

    pub fn offset2(v: Vec2i, d: Vec2i, max: Vec2i) Vec2i {
        const x = v + d;
        return @max(@min(x, max), @splat(2, @as(i32, 0)));
    }

    pub fn offset3(v: Vec4i, d: Vec4i, max: Vec4i) Vec4i {
        const x = v + d;
        return @max(@min(x, max), @splat(4, @as(i32, 0)));
    }
};

pub const Repeat = struct {
    pub fn f(x: f32) f32 {
        return math.frac(x);
    }

    pub fn f3(x: Vec4f) Vec4f {
        return math.frac(x);
    }

    pub fn increment(v: i32, max: i32) i32 {
        return if (v >= max) 0 else v + 1;
    }

    pub fn lowerBound(v: i32, max: i32) i32 {
        return if (v < 0) max else v;
    }

    pub fn offset(v: i32, d: i32, max: i32) i32 {
        const x = v + d;

        if (x > max) {
            return 0;
        }

        if (x < 0) {
            return max;
        }

        return x;
    }
};
