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
            .Clamp => math.clamp(x, 0.0, 1.0),
            .Repeat => math.frac(x),
        };
    }

    pub fn f3(m: Mode, x: Vec4f) Vec4f {
        return switch (m) {
            .Clamp => math.clamp4(x, 0.0, 1.0),
            .Repeat => math.frac(x),
        };
    }

    pub fn coord(m: Mode, c: i32, end: i32) i32 {
        return switch (m) {
            .Clamp => Clamp.coord(c, end),
            .Repeat => @mod(c, end),
        };
    }

    pub fn coord3(m: Mode, c: Vec4i, end: Vec4i) Vec4i {
        return switch (m) {
            .Clamp => Clamp.coord3(c, end),
            .Repeat => @mod(c, end),
        };
    }
};

const Clamp = struct {
    pub fn coord(c: i32, end: i32) i32 {
        const max = end - 1;
        return @max(@min(c, max), 0);
    }

    pub fn coord3(c: Vec4i, end: Vec4i) Vec4i {
        const max = end - Vec4i{ 1, 1, 1, 0 };
        return @max(@min(c, max), @as(Vec4i, @splat(0)));
    }
};
