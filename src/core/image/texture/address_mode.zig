const math = @import("base").math;

const std = @import("std");

pub const Clamp = struct {
    pub fn f(x: f32) f32 {
        return std.math.clamp(x, 0.0, 1.0);
    }
};

pub const Repeat = struct {
    pub fn f(x: f32) f32 {
        return math.frac(x);
    }
};
