const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Ray_max_t = 3.4027715434167032e+38;
pub const Almost_ray_max_t = 3.4027713405926072e+38;

// The following block implements the ray offset technique described in
// "A Fast and Robust Method for Avoiding Self-Intersection"

const origin: f32 = 1.0 / 32.0;
const float_scale: f32 = 1.0 / 65536.0;
const int_scale: f32 = 256.0;

pub fn offsetRay(p: Vec4f, n: Vec4f) Vec4f {
    const of_i = math.vec4fTo4i(@as(Vec4f, @splat(int_scale)) * Vec4f{ n[0], n[1], n[2], 0.0 });

    const p_i0 = @as(f32, @bitCast(@as(i32, @bitCast(p[0])) + (if (p[0] < 0.0) -of_i[0] else of_i[0])));
    const p_i1 = @as(f32, @bitCast(@as(i32, @bitCast(p[1])) + (if (p[1] < 0.0) -of_i[1] else of_i[1])));
    const p_i2 = @as(f32, @bitCast(@as(i32, @bitCast(p[2])) + (if (p[2] < 0.0) -of_i[2] else of_i[2])));

    return .{
        if (@abs(p[0]) < origin) @mulAdd(f32, float_scale, n[0], p[0]) else p_i0,
        if (@abs(p[1]) < origin) @mulAdd(f32, float_scale, n[1], p[1]) else p_i1,
        if (@abs(p[2]) < origin) @mulAdd(f32, float_scale, n[2], p[2]) else p_i2,
        0.0,
    };
}

pub fn offsetF(t: f32) f32 {
    return if (t < origin) t + float_scale else @as(f32, @bitCast(@as(i32, @bitCast(t)) + @as(i32, @intFromFloat(int_scale))));
}

pub fn offsetB(t: f32) f32 {
    return if (t < origin) t - float_scale else @as(f32, @bitCast(@as(i32, @bitCast(t)) - @as(i32, @intFromFloat(int_scale))));
}
