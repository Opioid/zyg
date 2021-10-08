const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub fn schlick1(wo_dot_h: f32, f0: f32) f32 {
    return f0 + math.pow5(1.0 - wo_dot_h) * (1.0 - f0);
}

pub const Schlick = struct {
    f0: Vec4f,

    pub fn init(f0: Vec4f) Schlick {
        return .{ .f0 = f0 };
    }

    pub fn f(self: Schlick, wo_dot_h: f32) Vec4f {
        return self.f0 + @splat(4, math.pow5(1.0 - wo_dot_h)) * (@splat(4, @as(f32, 1.0)) - self.f0);
    }

    pub fn F0(n0: f32, n1: f32) f32 {
        const t = (n0 - n1) / (n0 + n1);
        return t * t;
    }
};

pub fn dielectric(cos_theta_i: f32, cos_theta_t: f32, eta_i: f32, eta_t: f32) f32 {
    const t0 = eta_t * cos_theta_i;
    const t1 = eta_i * cos_theta_t;

    const r_p = (t0 - t1) / (t0 + t1);

    const t2 = eta_i * cos_theta_i;
    const t3 = eta_t * cos_theta_t;

    const r_o = (t2 - t3) / (t2 + t3);

    return 0.5 * (r_p * r_p + r_o * r_o);
}

pub fn conductor(eta: Vec4f, k: Vec4f, wo_dot_h: f32) Vec4f {
    const tmp_f = eta * eta + k * k;

    const wo_dot_h2 = @splat(4, wo_dot_h * wo_dot_h);
    const tmp = wo_dot_h2 * tmp_f;

    const a = @splat(4, 2.0 * wo_dot_h) * eta;
    const r_p = (tmp - a + @splat(4, @as(f32, 1.0))) / (tmp + a + @splat(4, @as(f32, 1.0)));

    const r_o = (tmp_f - a + wo_dot_h2) / (tmp_f + a + wo_dot_h2);

    return @splat(4, @as(f32, 0.5)) * (r_p + r_o);
}
