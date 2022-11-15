const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

pub const Mode = enum {
    Clamp,
    Repeat,
    ClampRepeat,
    RepeatClamp,

    pub fn f2(m: Mode, x: Vec2f) Vec2f {
        return switch (m) {
            .Clamp => Clamp.f(x),
            .ClampRepeat => .{ Clamp.f(x[0]), Repeat.f(x[1]) },
            .Repeat => Repeat.f(x),
            .RepeatClamp => .{ Repeat.f(x[0]), Clamp.f(x[1]) },
        };
    }

    pub fn f3(m: Mode, x: Vec4f) Vec4f {
        return switch (m) {
            .Clamp, .ClampRepeat => Clamp.f(x),
            .Repeat, .RepeatClamp => Repeat.f(x),
        };
    }

    pub fn increment2(m: Mode, v: Vec2i, max: Vec2i) Vec2i {
        return switch (m) {
            .Clamp => Clamp.increment2(v, max),
            .ClampRepeat => .{ Clamp.increment(v[0], max[0]), Repeat.increment(v[1], max[1]) },
            .Repeat => Repeat.increment2(v, max),
            .RepeatClamp => .{ Repeat.increment(v[0], max[0]), Clamp.increment(v[1], max[1]) },
        };
    }

    pub fn increment3(m: Mode, v: Vec4i, max: Vec4i) Vec4i {
        return switch (m) {
            .Clamp, .ClampRepeat => Clamp.increment3(v, max),
            .Repeat, .RepeatClamp => Repeat.increment3(v, max),
        };
    }

    pub fn lowerBound2(m: Mode, v: Vec2i, max: Vec2i) Vec2i {
        return switch (m) {
            .Clamp => Clamp.lowerBound2(v),
            .ClampRepeat => .{ Clamp.lowerBound(v[0]), Repeat.lowerBound(v[1], max[1]) },
            .Repeat => Repeat.lowerBound2(v, max),
            .RepeatClamp => .{ Repeat.lowerBound(v[0], max[0]), Clamp.lowerBound(v[1]) },
        };
    }

    pub fn lowerBound3(m: Mode, v: Vec4i, max: Vec4i) Vec4i {
        return switch (m) {
            .Clamp, .ClampRepeat => Clamp.lowerBound3(v),
            .Repeat, .RepeatClamp => Repeat.lowerBound3(v, max),
        };
    }
};

const Clamp = struct {
    pub fn f(x: anytype) @TypeOf(x) {
        return math.clamp(x, 0.0, 1.0);
    }

    pub fn increment(v: i32, max: i32) i32 {
        return @min(v + 1, max);
    }

    pub fn increment2(v: Vec2i, max: Vec2i) Vec2i {
        return @min(v + Vec2i{ 1, 1 }, max);
    }

    pub fn increment3(v: Vec4i, max: Vec4i) Vec4i {
        return @min(v + Vec4i{ 1, 1, 1, 0 }, max);
    }

    pub fn lowerBound(v: i32) i32 {
        return @max(v, 0);
    }

    pub fn lowerBound2(v: Vec2i) Vec2i {
        return @max(v, @splat(2, @as(i32, 0)));
    }

    pub fn lowerBound3(v: Vec4i) Vec4i {
        return @max(v, @splat(4, @as(i32, 0)));
    }
};

const Repeat = struct {
    pub fn f(x: anytype) @TypeOf(x) {
        return math.frac(x);
    }

    pub fn increment(v: i32, max: i32) i32 {
        return if (v >= max) 0 else v + 1;
    }

    pub fn increment2(v: Vec2i, max: Vec2i) Vec2i {
        return @select(i32, v >= max, Vec2i{ 0, 0 }, v + Vec2i{ 1, 1 });
    }

    pub fn increment3(v: Vec4i, max: Vec4i) Vec4i {
        return @select(i32, v >= max, Vec4i{ 0, 0, 0, 0 }, v + Vec4i{ 1, 1, 1, 0 });
    }

    pub fn lowerBound(v: i32, max: i32) i32 {
        return if (v < 0) max else v;
    }

    pub fn lowerBound2(v: Vec2i, max: Vec2i) Vec2i {
        return @select(i32, v < Vec2i{ 0, 0 }, max, v);
    }

    pub fn lowerBound3(v: Vec4i, max: Vec4i) Vec4i {
        return @select(i32, v < Vec4i{ 0, 0, 0, 0 }, max, v);
    }
};
