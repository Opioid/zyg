const math = @import("base").math;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

pub const Ray_max_t = 2.14748313e+09;
pub const Almost_ray_max_t = 2.14748300e+09;

// The following block implements the ray offset technique described in
// "A Fast and Robust Method for Avoiding Self-Intersection"

const origin: f32 = 1.0 / 32.0;
const float_scale: f32 = 1.0 / 65536.0;
const int_scale: f32 = 256.0;

pub fn offsetRay(p: Vec4f, n: Vec4f) Vec4f {
    const of_i = math.vec4fTo4i(@as(Vec4f, @splat(int_scale)) * n);

    const p_ii: Vec4i = @bitCast(p);
    const p_in: Vec4f = @bitCast(p_ii - of_i);
    const p_ip: Vec4f = @bitCast(p_ii + of_i);
    const p_i = @select(f32, p < @as(Vec4f, @splat(0.0)), p_in, p_ip);

    const mad = @mulAdd(Vec4f, @splat(float_scale), n, p);

    const r = @select(f32, @abs(p) < @as(Vec4f, @splat(origin)), mad, p_i);

    return .{ r[0], r[1], r[2], 0.0 };
}

pub fn offsetF(t: f32) f32 {
    return if (t < origin) t + float_scale else @as(f32, @bitCast(@as(i32, @bitCast(t)) + @as(i32, @intFromFloat(int_scale))));
}

pub fn offsetB(t: f32) f32 {
    return if (t < origin) t - float_scale else @as(f32, @bitCast(@as(i32, @bitCast(t)) - @as(i32, @intFromFloat(int_scale))));
}
