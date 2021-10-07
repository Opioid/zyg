const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const CC = struct {
    a: Vec4f,
    s: Vec4f,
};

pub fn attenuation(ac: Vec4f, ssc: Vec4f, distance: f32, g: f32) CC {
    const mu_t = attenutionCoefficient(ac, distance);
    return scattering(mu_t, ssc, g);
}

pub fn attenutionCoefficient(color: Vec4f, distance: f32) Vec4f {
    const ca = math.clamp(color, 0.01, 0.991102);
    const a = @log(ca);

    return -a / @splat(4, distance);
}

pub fn scattering(mu_t: Vec4f, ssc: Vec4f, g: f32) CC {
    const root = @sqrt(@splat(4, @as(f32, 9.59217)) + @splat(4, @as(f32, 41.6808)) *
        ssc + @splat(4, @as(f32, 17.7126)) * ssc * ssc);
    const factor = math.clamp(@splat(4, @as(f32, 4.097125)) +
        @splat(4, @as(f32, 4.20863)) * ssc - root, 0.0, 1.0);
    const fsq = factor * factor;
    const pss = (@splat(4, @as(f32, 1.0)) - fsq) / (@splat(4, @as(f32, 1.0)) - @splat(4, @as(f32, g)) * fsq);
    const mu_a = mu_t * (@splat(4, @as(f32, 1.0)) - pss);

    return .{ .a = mu_a, .s = mu_t - mu_a };
}
