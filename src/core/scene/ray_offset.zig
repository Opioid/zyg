const Vec4f = @import("base").math.Vec4f;

const std = @import("std");

// The following block implements the ray offset technique described in
// "A Fast and Robust Method for Avoiding Self-Intersection"

const origin = 1.0 / 32.0;
const float_scale = 1.0 / 65536.0;
const int_scale = 256.0;

pub fn offsetRay(p: Vec4f, n: Vec4f) Vec4f {
    const of_i = n.mulScalar3(int_scale).toVec4i();

    const p_i = Vec4f.init3(
        @bitCast(f32, @bitCast(i32, p.v[0]) + if (p.v[0] < 0.0) -of_i.v[0] else of_i.v[0]),
        @bitCast(f32, @bitCast(i32, p.v[1]) + if (p.v[1] < 0.0) -of_i.v[1] else of_i.v[1]),
        @bitCast(f32, @bitCast(i32, p.v[2]) + if (p.v[2] < 0.0) -of_i.v[2] else of_i.v[2]),
    );

    return Vec4f.init3(
        if (@fabs(p.v[0]) < origin) std.math.fma(f32, float_scale, n.v[0], p.v[0]) else p_i.v[0],
        if (@fabs(p.v[1]) < origin) std.math.fma(f32, float_scale, n.v[1], p.v[1]) else p_i.v[1],
        if (@fabs(p.v[2]) < origin) std.math.fma(f32, float_scale, n.v[2], p.v[2]) else p_i.v[2],
    );
}

pub fn offsetF(t: f32) f32 {
    return if (t < origin) t + float_scale else @bitCast(f32, @bitCast(i32, t) + @floatToInt(i32, int_scale));
}
