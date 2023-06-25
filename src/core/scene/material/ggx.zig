const bxdf = @import("bxdf.zig");
const smplbase = @import("sample_base.zig");
const Frame = smplbase.Frame;
const IoR = smplbase.IoR;
const hlp = @import("sample_helper.zig");
const integral = @import("ggx_integral.zig");

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Min_roughness: f32 = 0.01314;
pub const Min_alpha: f32 = Min_roughness * Min_roughness;

const E_m_tex = math.InterpolatedFunction2D_N(
    integral.E_m_size,
    integral.E_m_size,
).fromArray(&integral.E_m);

const E_m_avg_tex = math.InterpolatedFunction1D_N(integral.E_m_avg.len).fromArray(&integral.E_m_avg);

const E_s_tex = math.InterpolatedFunction3D_N(
    integral.E_s_size,
    integral.E_s_size,
    integral.E_s_size,
).fromArray(&integral.E_s);

pub fn ilmEpDielectric(n_dot_wo: f32, alpha: f32, f0: f32) f32 {
    return 1.0 / E_s_tex.eval(n_dot_wo, alpha, f0 * integral.E_s_inverse_max_f0);
}

pub fn dspbrMicroEc(f0: Vec4f, n_dot_wi: f32, n_dot_wo: f32, alpha: f32) Vec4f {
    const e_wo = E_m_tex.eval(n_dot_wo, alpha);
    const e_wi = E_m_tex.eval(n_dot_wi, alpha);
    const e_avg = E_m_avg_tex.eval(alpha);

    const m = ((1.0 - e_wo) * (1.0 - e_wi)) / (std.math.pi * (1.0 - e_avg));

    const f_avg = @splat(4, @as(f32, 20.0 / 21.0)) * f0;

    const f = ((f_avg * f_avg) * @splat(4, e_avg)) / (@splat(4, @as(f32, 1.0)) - f_avg * @splat(4, 1.0 - e_avg));

    return @splat(4, m) * f;
}

pub fn clampRoughness(roughness: f32) f32 {
    return math.max(roughness, Min_roughness);
}

pub fn mapRoughness(roughness: f32) f32 {
    return roughness * (1.0 - Min_roughness) + Min_roughness;
}

const ResultF = struct { r: bxdf.Result, f: Vec4f };

pub const Iso = struct {
    pub inline fn reflection(
        h: Vec4f,
        n: Vec4f,
        n_dot_wi: f32,
        n_dot_wo: f32,
        wo_dot_h: f32,
        alpha: f32,
        fresnel: anytype,
    ) bxdf.Result {
        return reflectionF(h, n, n_dot_wi, n_dot_wo, wo_dot_h, alpha, fresnel).r;
    }

    pub fn reflectionF(
        h: Vec4f,
        n: Vec4f,
        n_dot_wi: f32,
        n_dot_wo: f32,
        wo_dot_h: f32,
        alpha: f32,
        fresnel: anytype,
    ) ResultF {
        const alpha2 = alpha * alpha;

        const n_dot_h = math.saturate(math.dot3(n, h));

        const d = distribution(n_dot_h, alpha2);
        const g = visibilityAndG1Wo(n_dot_wi, n_dot_wo, alpha2);
        const f = fresnel.f(wo_dot_h);

        //   fresnel_result.* = f;

        const refl = @splat(4, d * g[0]) * f;
        const pdf = pdfVisible(d, g[1]);

        return .{ .r = bxdf.Result.init(refl, pdf), .f = f };
    }

    pub fn reflect(
        wo: Vec4f,
        n_dot_wo: f32,
        alpha: f32,
        xi: Vec2f,
        fresnel: anytype,
        frame: Frame,
        result: *bxdf.Sample,
    ) f32 {
        var n_dot_h: f32 = undefined;
        const h = Aniso.sample(wo, @splat(2, alpha), xi, frame, &n_dot_h);

        const wo_dot_h = hlp.clampDot(wo, h);
        const wi = math.normalize3(@splat(4, 2.0 * wo_dot_h) * h - wo);

        const n_dot_wi = frame.clampNdot(wi);
        const alpha2 = alpha * alpha;

        const d = distribution(n_dot_h, alpha2);
        const g = visibilityAndG1Wo(n_dot_wi, n_dot_wo, alpha2);
        const f = fresnel.f(wo_dot_h);

        result.reflection = @splat(4, d * g[0]) * f;
        result.wi = wi;
        result.h = h;
        result.pdf = pdfVisible(d, g[1]);
        result.h_dot_wi = wo_dot_h;
        result.class = if (alpha <= Min_alpha) .{ .specular = true, .reflection = true } else .{ .glossy = true, .reflection = true };

        return n_dot_wi;
    }

    pub fn refraction(
        n_dot_wi: f32,
        n_dot_wo: f32,
        wi_dot_h: f32,
        wo_dot_h: f32,
        n_dot_h: f32,
        alpha: f32,
        ior: IoR,
        fresnel: anytype,
    ) bxdf.Result {
        const alpha2 = alpha * alpha;

        const abs_wi_dot_h = hlp.clampAbs(wi_dot_h);
        const abs_wo_dot_h = hlp.clampAbs(wo_dot_h);

        const d = distribution(n_dot_h, alpha2);
        const g = gSmithCorrelated(n_dot_wi, n_dot_wo, alpha2);

        const cos_x = if (ior.eta_i > ior.eta_t) abs_wi_dot_h else abs_wo_dot_h;
        const f = 1.0 - fresnel.f(cos_x)[0];

        const sqr_eta_t = ior.eta_t * ior.eta_t;

        const factor = (abs_wi_dot_h * abs_wo_dot_h) / (n_dot_wi * n_dot_wo);
        const denom = math.pow2(ior.eta_i * wo_dot_h + ior.eta_t * wi_dot_h);

        const refr = d * g * f;
        const refl = (factor * sqr_eta_t / denom) * refr;

        const pdf = pdfVisibleRefract(n_dot_wo, abs_wo_dot_h, d, alpha2);

        return bxdf.Result.init(@splat(4, refl), pdf * f * (abs_wi_dot_h * sqr_eta_t / denom));
    }

    pub fn reflectNoFresnel(
        wo: Vec4f,
        h: Vec4f,
        n_dot_wo: f32,
        n_dot_h: f32,
        wi_dot_h: f32,
        wo_dot_h: f32,
        alpha: f32,
        frame: Frame,
        result: *bxdf.Sample,
    ) f32 {
        const wi = math.normalize3(@splat(4, 2.0 * wo_dot_h) * h - wo);

        const n_dot_wi = frame.clampNdot(wi);
        const alpha2 = alpha * alpha;

        const d = distribution(n_dot_h, alpha2);
        const g = visibilityAndG1Wo(n_dot_wi, n_dot_wo, alpha2);

        result.reflection = @splat(4, d * g[0]);
        result.wi = wi;
        result.h = h;
        result.pdf = pdfVisible(d, g[1]);
        result.h_dot_wi = wi_dot_h;
        result.class = if (alpha <= Min_alpha) .{ .specular = true, .reflection = true } else .{ .glossy = true, .reflection = true };

        return n_dot_wi;
    }

    pub fn refractNoFresnel(
        wo: Vec4f,
        h: Vec4f,
        n_dot_wo: f32,
        n_dot_h: f32,
        wi_dot_h: f32,
        wo_dot_h: f32,
        alpha: f32,
        ior: IoR,
        frame: Frame,
        result: *bxdf.Sample,
    ) f32 {
        const eta = ior.eta_i / ior.eta_t;

        const abs_wi_dot_h = hlp.clampAbs(wi_dot_h);
        const abs_wo_dot_h = hlp.clampAbs(wo_dot_h);

        const wi = math.normalize3(@splat(4, eta * abs_wo_dot_h - abs_wi_dot_h) * h - @splat(4, eta) * wo);

        const n_dot_wi = frame.clampAbsNdot(wi);

        const alpha2 = alpha * alpha;

        const d = distribution(n_dot_h, alpha2);
        const g = gSmithCorrelated(n_dot_wi, n_dot_wo, alpha2);

        const refr = d * g;
        const factor = (abs_wi_dot_h * abs_wo_dot_h) / (n_dot_wi * n_dot_wo);
        const denom = math.pow2(ior.eta_i * wo_dot_h + ior.eta_t * wi_dot_h);
        const sqr_eta_t = ior.eta_t * ior.eta_t;
        const pdf = pdfVisibleRefract(n_dot_wo, abs_wo_dot_h, d, alpha2);

        result.reflection = @splat(4, (factor * sqr_eta_t / denom) * refr);
        result.wi = wi;
        result.h = h;
        result.pdf = pdf * (abs_wi_dot_h * sqr_eta_t / denom);
        result.h_dot_wi = wi_dot_h;
        result.class = if (alpha <= Min_alpha) .{ .specular = true, .transmission = true } else .{ .glossy = true, .transmission = true };

        return n_dot_wi;
    }

    fn distribution(n_dot_h: f32, a2: f32) f32 {
        const d = (n_dot_h * n_dot_h) * (a2 - 1.0) + 1.0;
        return a2 / (std.math.pi * d * d);
    }

    fn visibilityAndG1Wo(n_dot_wi: f32, n_dot_wo: f32, alpha2: f32) Vec2f {
        const n_dot = Vec4f{ n_dot_wi, n_dot_wo, 0.0, 0.0 };
        const a2 = @splat(4, alpha2);

        const t = @sqrt(a2 + (@splat(4, @as(f32, 1.0)) - a2) * (n_dot * n_dot));

        const t_wi = t[0];
        const t_wo = t[1];

        return .{ 0.5 / (n_dot_wi * t_wo + n_dot_wo * t_wi), t_wo + n_dot_wo };
    }

    fn gSmithCorrelated(n_dot_wi: f32, n_dot_wo: f32, alpha2: f32) f32 {
        const a = n_dot_wo * @sqrt(alpha2 + (1.0 - alpha2) * (n_dot_wi * n_dot_wi));
        const b = n_dot_wi * @sqrt(alpha2 + (1.0 - alpha2) * (n_dot_wo * n_dot_wo));

        return (2.0 * n_dot_wi * n_dot_wo) / (a + b);
    }
};

pub const Aniso = struct {
    pub inline fn reflection(
        wi: Vec4f,
        wo: Vec4f,
        h: Vec4f,
        n_dot_wi: f32,
        n_dot_wo: f32,
        wo_dot_h: f32,
        alpha: Vec2f,
        fresnel: anytype,
        frame: Frame,
    ) bxdf.Result {
        return reflectionF(wi, wo, h, n_dot_wi, n_dot_wo, wo_dot_h, alpha, fresnel, frame).r;
    }

    pub fn reflectionF(
        wi: Vec4f,
        wo: Vec4f,
        h: Vec4f,
        n_dot_wi: f32,
        n_dot_wo: f32,
        wo_dot_h: f32,
        alpha: Vec2f,
        fresnel: anytype,
        frame: Frame,
    ) ResultF {
        if (alpha[0] == alpha[1]) {
            return Iso.reflectionF(h, frame.n, n_dot_wi, n_dot_wo, wo_dot_h, alpha[0], fresnel);
        }

        const n_dot_h = math.saturate(math.dot3(frame.n, h));
        const x_dot_h = math.dot3(frame.t, h);
        const y_dot_h = math.dot3(frame.b, h);

        const d = distribution(n_dot_h, x_dot_h, y_dot_h, alpha);

        const t_dot_wi = math.dot3(frame.t, wi);
        const t_dot_wo = math.dot3(frame.t, wo);
        const b_dot_wi = math.dot3(frame.b, wi);
        const b_dot_wo = math.dot3(frame.b, wo);

        const g = visibilityAndG1Wo(t_dot_wi, t_dot_wo, b_dot_wi, b_dot_wo, n_dot_wi, n_dot_wo, alpha);

        const f = fresnel.f(wo_dot_h);

        const refl = @splat(4, d * g[0]) * f;
        const pdf = pdfVisible(d, g[1]);

        return .{ .r = bxdf.Result.init(refl, pdf), .f = f };
    }

    pub fn reflect(
        wo: Vec4f,
        n_dot_wo: f32,
        alpha: Vec2f,
        xi: Vec2f,
        fresnel: anytype,
        frame: Frame,
        result: *bxdf.Sample,
    ) f32 {
        if (alpha[0] == alpha[1]) {
            return Iso.reflect(wo, n_dot_wo, alpha[0], xi, fresnel, frame, result);
        }

        var n_dot_h: f32 = undefined;
        const h = sample(wo, alpha, xi, frame, &n_dot_h);

        const x_dot_h = math.dot3(frame.t, h);
        const y_dot_h = math.dot3(frame.b, h);

        const wo_dot_h = hlp.clampDot(wo, h);

        const wi = math.normalize3(@splat(4, 2.0 * wo_dot_h) * h - wo);

        const n_dot_wi = frame.clampNdot(wi);

        const d = distribution(n_dot_h, x_dot_h, y_dot_h, alpha);

        const t_dot_wi = math.dot3(frame.t, wi);
        const t_dot_wo = math.dot3(frame.t, wo);
        const b_dot_wi = math.dot3(frame.b, wi);
        const b_dot_wo = math.dot3(frame.b, wo);

        const g = visibilityAndG1Wo(t_dot_wi, t_dot_wo, b_dot_wi, b_dot_wo, n_dot_wi, n_dot_wo, alpha);

        const f = fresnel.f(wo_dot_h);

        result.reflection = @splat(4, d * g[0]) * f;
        result.wi = wi;
        result.h = h;
        result.pdf = pdfVisible(d, g[1]);
        result.h_dot_wi = wo_dot_h;
        result.class = if (alpha[1] <= Min_alpha) .{ .specular = true, .reflection = true } else .{ .glossy = true, .reflection = true };

        return n_dot_wi;
    }

    pub fn reflectNoFresnel(
        wo: Vec4f,
        h: Vec4f,
        n_dot_wo: f32,
        n_dot_h: f32,
        wi_dot_h: f32,
        wo_dot_h: f32,
        alpha: Vec2f,
        frame: Frame,
        result: *bxdf.Sample,
    ) f32 {
        if (alpha[0] == alpha[1]) {
            return Iso.reflectNoFresnel(wo, h, n_dot_wo, n_dot_h, wi_dot_h, wo_dot_h, alpha[0], frame, result);
        }

        const x_dot_h = math.dot3(frame.t, h);
        const y_dot_h = math.dot3(frame.b, h);

        const wi = math.normalize3(@splat(4, 2.0 * wo_dot_h) * h - wo);

        const n_dot_wi = frame.clampNdot(wi);

        const d = distribution(n_dot_h, x_dot_h, y_dot_h, alpha);

        const t_dot_wi = math.dot3(frame.t, wi);
        const t_dot_wo = math.dot3(frame.t, wo);
        const b_dot_wi = math.dot3(frame.b, wi);
        const b_dot_wo = math.dot3(frame.b, wo);

        const g = visibilityAndG1Wo(t_dot_wi, t_dot_wo, b_dot_wi, b_dot_wo, n_dot_wi, n_dot_wo, alpha);

        result.reflection = @splat(4, d * g[0]);
        result.wi = wi;
        result.h = h;
        result.pdf = pdfVisible(d, g[1]);
        result.h_dot_wi = wi_dot_h;
        result.class = if (alpha[1] <= Min_alpha) .{ .specular = true, .reflection = true } else .{ .glossy = true, .reflection = true };

        return n_dot_wi;
    }

    // Sampling Visible GGX Normals with Spherical Caps
    // Jonathan Dupuy, Anis Benyoub
    // https://arxiv.org/pdf/2306.05044.pdf

    pub fn sample(wo: Vec4f, alpha: Vec2f, xi: Vec2f, frame: Frame, n_dot_h: *f32) Vec4f {
        const lwo = frame.worldToTangent(wo);
        const v = math.normalize3(.{ alpha[0] * lwo[0], alpha[1] * lwo[1], lwo[2], 0.0 });

        const phi = 2.0 * std.math.pi * xi[0];
        const z = @mulAdd(f32, 1.0 - xi[1], 1.0 + v[2], -v[2]);
        const sin_theta = @sqrt(math.saturate(1.0 - z * z));
        const x = sin_theta * @cos(phi);
        const y = sin_theta * @sin(phi);

        const h = Vec4f{ x, y, z, 0.0 } + v;
        const m = math.normalize3(.{ alpha[0] * h[0], alpha[1] * h[1], h[2], 0.0 });

        n_dot_h.* = hlp.clamp(m[2]);

        return frame.tangentToWorld(m);
    }

    fn distribution(n_dot_h: f32, x_dot_h: f32, y_dot_h: f32, a: Vec2f) f32 {
        const a2 = a * a;

        const x = (x_dot_h * x_dot_h) / a2[0];
        const y = (y_dot_h * y_dot_h) / a2[1];
        const d = (x + y) + (n_dot_h * n_dot_h);

        return 1.0 / (std.math.pi * (a[0] * a[1]) * (d * d));
    }

    fn visibilityAndG1Wo(
        t_dot_wi: f32,
        t_dot_wo: f32,
        b_dot_wi: f32,
        b_dot_wo: f32,
        n_dot_wi: f32,
        n_dot_wo: f32,
        a: Vec2f,
    ) Vec2f {
        const t_wo = math.length3(.{ a[0] * t_dot_wo, a[1] * b_dot_wo, n_dot_wo, 0.0 });
        const t_wi = math.length3(.{ a[0] * t_dot_wi, a[1] * b_dot_wi, n_dot_wi, 0.0 });

        return .{ 0.5 / (n_dot_wi * t_wo + n_dot_wo * t_wi), t_wo + n_dot_wo };
    }
};

fn pdfVisible(d: f32, g1_wo: f32) f32 {
    return (0.5 * d) / g1_wo;
}

fn pdfVisibleRefract(n_dot_wo: f32, wo_dot_h: f32, d: f32, alpha2: f32) f32 {
    const g1 = G_ggx(n_dot_wo, alpha2);

    return (g1 * wo_dot_h * d / n_dot_wo);
}

fn G_ggx(n_dot_v: f32, alpha2: f32) f32 {
    return (2.0 * n_dot_v) / (n_dot_v + @sqrt(alpha2 + (1.0 - alpha2) * (n_dot_v * n_dot_v)));
}
