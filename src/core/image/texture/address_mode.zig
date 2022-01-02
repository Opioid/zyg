const math = @import("base").math;

const std = @import("std");

pub const Mode = union(enum) {
    Clamp: Clamp,
    Repeat: Repeat,

    pub fn f(m: Mode, x: f32) f32 {
        return switch (m) {
            .Clamp => Clamp.f(x),
            .Repeat => Repeat.f(x),
        };
    }

    pub fn increment(m: Mode, v: i32, max: i32) i32 {
        return switch (m) {
            .Clamp => Clamp.increment(v, max),
            .Repeat => Repeat.increment(v, max),
        };
    }

    pub fn lowerBound(m: Mode, v: i32, max: i32) i32 {
        return switch (m) {
            .Clamp => Clamp.lowerBound(v, max),
            .Repeat => Repeat.lowerBound(v, max),
        };
    }
};

pub const Clamp = struct {
    pub fn f(x: f32) f32 {
        return std.math.clamp(x, 0.0, 1.0);
    }

    pub fn increment(v: i32, max: i32) i32 {
        if (v >= max) {
            return max;
        }

        return v + 1;
    }

    pub fn lowerBound(v: i32, max: i32) i32 {
        _ = max;

        if (v < 0) {
            return 0;
        }

        return v;
    }
};

pub const Repeat = struct {
    pub fn f(x: f32) f32 {
        return math.frac(x);
    }

    pub fn increment(v: i32, max: i32) i32 {
        if (v >= max) {
            return 0;
        }

        return v + 1;
    }

    pub fn lowerBound(v: i32, max: i32) i32 {
        if (v < 0) {
            return max;
        }

        return v;
    }
};
