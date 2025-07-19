const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const CC = struct {
    a: Vec4f,
    s: Vec4f,

    pub fn anisotropy(self: CC) f32 {
        return self.a[3];
    }

    pub fn scaled(self: CC, x: Vec4f) CC {
        const a = self.a;
        const ax = a * x;
        return .{ .a = .{ ax[0], ax[1], ax[2], a[3] }, .s = self.s * x };
    }

    pub fn minorantMajorantT(self: CC) Vec2f {
        const mu_t = self.a + self.s;
        return .{ math.hmin3(mu_t), math.hmax3(mu_t) };
    }
};

pub const CCE = struct {
    cc: CC,
    e: Vec4f,
};

pub fn attenuation(ac: Vec4f, ssc: Vec4f, distance: f32, g: f32) CC {
    const mu_t = attenuationCoefficient(ac, distance);
    return scattering(mu_t, ssc, g);
}

pub fn attenuationCoefficient(color: Vec4f, distance: f32) Vec4f {
    if (0.0 == distance) {
        return @splat(0.0);
    }

    const ca = math.clamp4(color, @splat(0.01), @splat(0.991102));
    const a = @log(ca);

    return -a / @as(Vec4f, @splat(distance));
}

pub fn scattering(mu_t: Vec4f, ssc: Vec4f, g: f32) CC {
    const root = @sqrt(@as(Vec4f, @splat(9.59217)) + ssc * (@as(Vec4f, @splat(41.6808)) + ssc * @as(Vec4f, @splat(17.7126))));
    const factor = math.clamp4(@as(Vec4f, @splat(4.097125)) + @as(Vec4f, @splat(4.20863)) * ssc - root, @splat(0.0), @splat(1.0));

    const fsq = factor * factor;
    const pss = (@as(Vec4f, @splat(1.0)) - fsq) / (@as(Vec4f, @splat(1.0)) - @as(Vec4f, @splat(g)) * fsq);

    const mu_a = mu_t * (@as(Vec4f, @splat(1.0)) - pss);
    const mu_s = mu_t - mu_a;

    return .{ .a = .{ mu_a[0], mu_a[1], mu_a[2], g }, .s = .{ mu_s[0], mu_s[1], mu_s[2], 1.0 } };
}

pub inline fn attenuation1(c: f32, distance: f32) f32 {
    return @exp(-distance * c);
}

pub inline fn attenuation3(c: Vec4f, distance: f32) Vec4f {
    return @exp(@as(Vec4f, @splat(-distance)) * c);
}
