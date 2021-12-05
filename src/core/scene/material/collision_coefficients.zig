const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const CC = struct {
    a: Vec4f,
    s: Vec4f,
};

pub const CM = struct {
    minorant_mu_a: f32,
    minorant_mu_s: f32,
    majorant_mu_a: f32,
    majorant_mu_s: f32,

    pub fn initCC(cc: CC) CM {
        return .{
            .minorant_mu_a = math.minComponent3(cc.a),
            .minorant_mu_s = math.minComponent3(cc.s),
            .majorant_mu_a = math.maxComponent3(cc.a),
            .majorant_mu_s = math.maxComponent3(cc.s),
        };
    }

    pub fn minorant_mu_t(self: CM) f32 {
        return self.minorant_mu_a + self.minorant_mu_s;
    }

    pub fn majorant_mu_t(self: CM) f32 {
        return self.majorant_mu_a + self.majorant_mu_s;
    }

    pub fn isEmpty(self: CM) bool {
        return 0.0 == self.majorant_mu_a and 0.0 == self.majorant_mu_s;
    }
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
