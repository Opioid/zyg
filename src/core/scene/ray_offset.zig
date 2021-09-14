const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");

// The following block implements the ray offset technique described in
// "A Fast and Robust Method for Avoiding Self-Intersection"

const origin = 1.0 / 32.0;
const float_scale = 1.0 / 65536.0;
const int_scale: f32 = 256.0;

pub fn offsetRay(p: Vec4f, n: Vec4f) Vec4f {
    const of_i = math.vec4f_to_i(@splat(4, int_scale) * n);

    const p_i = Vec4f{
        @bitCast(f32, @bitCast(i32, p[0]) + if (p[0] < 0.0) -of_i.v[0] else of_i.v[0]),
        @bitCast(f32, @bitCast(i32, p[1]) + if (p[1] < 0.0) -of_i.v[1] else of_i.v[1]),
        @bitCast(f32, @bitCast(i32, p[2]) + if (p[2] < 0.0) -of_i.v[2] else of_i.v[2]),
        0.0,
    };

    return .{
        if (@fabs(p[0]) < origin) std.math.fma(f32, float_scale, n[0], p[0]) else p_i[0],
        if (@fabs(p[1]) < origin) std.math.fma(f32, float_scale, n[1], p[1]) else p_i[1],
        if (@fabs(p[2]) < origin) std.math.fma(f32, float_scale, n[2], p[2]) else p_i[2],
        0.0,
    };
}

pub fn offsetF(t: f32) f32 {
    return if (t < origin) t + float_scale else @bitCast(f32, @bitCast(i32, t) + @floatToInt(i32, int_scale));
}
