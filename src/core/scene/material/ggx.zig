const bxdf = @import("bxdf.zig");
const Layer = @import("sample_base.zig").Layer;
const hlp = @import("sample_helper.zig");
const integral = @import("ggx_integral.zig");
const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Min_roughness: f32 = 0.01314;
pub const Min_alpha: f32 = Min_roughness * Min_roughness;

const E_tex = math.InterpolatedFunction_2D_N(integral.E_size, integral.E_size).fromArray(&integral.E);

pub fn ilmEpConductor(f0: Vec4f, n_dot_wo: f32, alpha: f32, metallic: f32) Vec4f {
    return @splat(4, @as(f32, 1.0)) + @splat(4, metallic / E_tex.eval(n_dot_wo, alpha) - 1.0) * f0;
}

pub fn clampRoughness(roughness: f32) f32 {
    return std.math.max(roughness, Min_roughness);
}

pub fn mapRoughness(roughness: f32) f32 {
    return roughness * (1.0 - Min_roughness) + Min_roughness;
}

pub const Iso = struct {
    pub fn reflection(
        n_dot_wi: f32,
        n_dot_wo: f32,
        wo_dot_h: f32,
        n_dot_h: f32,
        alpha: f32,
        fresnel: anytype,
    ) bxdf.Result {
        const alpha2 = alpha * alpha;

        const d = distribution(n_dot_h, alpha2);
        const g = visibilityAndG1Wo(n_dot_wi, n_dot_wo, alpha2);
        const f = fresnel.f(wo_dot_h);

        const refl = @splat(4, d * g[0]) * f;
        const pdf = pdfVisible(d, g[1]);

        return bxdf.Result.init(refl, pdf);
    }

    pub fn reflect(
        wo: Vec4f,
        n_dot_wo: f32,
        alpha: f32,
        xi: Vec2f,
        fresnel: anytype,
        layer: Layer,
        result: *bxdf.Sample,
    ) f32 {
        var n_dot_h: f32 = undefined;
        const h = Aniso.sample(wo, @splat(2, alpha), xi, layer, &n_dot_h);

        const wo_dot_h = hlp.clampDot(wo, h);

        const wi = math.normalize3(@splat(4, 2.0 * wo_dot_h) * h - wo);

        const n_dot_wi = layer.clampNdot(wi);
        const alpha2 = alpha * alpha;

        const d = distribution(n_dot_h, alpha2);
        const g = visibilityAndG1Wo(n_dot_wi, n_dot_wo, alpha2);
        const f = fresnel.f(wo_dot_h);

        result.reflection = @splat(4, d * g[0]) * f;
        result.wi = wi;
        result.h = h;
        result.pdf = pdfVisible(d, g[1]);
        result.h_dot_wi = wo_dot_h;
        result.typef.clearWith(.Glossy_reflection);

        return n_dot_wi;
    }

    fn distribution(n_dot_h: f32, a2: f32) f32 {
        const d = (n_dot_h * n_dot_h) * (a2 - 1.0) + 1.0;
        return a2 / (std.math.pi * d * d);
    }

    fn visibilityAndG1Wo(n_dot_wi: f32, n_dot_wo: f32, alpha2: f32) Vec2f {
        //    float const t_wi = std::sqrt(alpha2 + (1.f - alpha2) * (n_dot_wi * n_dot_wi));
        //    float const t_wo = std::sqrt(alpha2 + (1.f - alpha2) * (n_dot_wo * n_dot_wo));

        const n_dot = Vec4f{ n_dot_wi, n_dot_wo, n_dot_wi, n_dot_wo };
        const a2 = @splat(4, alpha2);

        const t = @sqrt(a2 + (@splat(4, @as(f32, 1.0)) - a2) * (n_dot * n_dot));

        const t_wi = t[0];
        const t_wo = t[1];

        return .{ 0.5 / (n_dot_wi * t_wo + n_dot_wo * t_wi), t_wo + n_dot_wo };
    }
};

pub const Aniso = struct {
    pub fn reflection(
        wi: Vec4f,
        wo: Vec4f,
        h: Vec4f,
        n_dot_wi: f32,
        n_dot_wo: f32,
        wo_dot_h: f32,
        alpha: Vec2f,
        fresnel: anytype,
        layer: Layer,
    ) bxdf.Result {
        const n_dot_h = math.saturate(math.dot3(layer.n, h));

        if (alpha[0] == alpha[1]) {
            return Iso.reflection(n_dot_wi, n_dot_wo, wo_dot_h, n_dot_h, alpha[0], fresnel);
        }

        const x_dot_h = math.dot3(layer.t, h);
        const y_dot_h = math.dot3(layer.b, h);

        const d = distribution(n_dot_h, x_dot_h, y_dot_h, alpha);

        const t_dot_wi = math.dot3(layer.t, wi);
        const t_dot_wo = math.dot3(layer.t, wo);
        const b_dot_wi = math.dot3(layer.b, wi);
        const b_dot_wo = math.dot3(layer.b, wo);

        const g = visibilityAndG1Wo(t_dot_wi, t_dot_wo, b_dot_wi, b_dot_wo, n_dot_wi, n_dot_wo, alpha);

        const f = fresnel.f(wo_dot_h);

        const refl = @splat(4, d * g[0]) * f;
        const pdf = pdfVisible(d, g[1]);

        //  SOFT_ASSERT(testing::check(reflection, h, n_dot_wi, n_dot_wo, wo_dot_h, pdf, layer));

        return bxdf.Result.init(refl, pdf);
    }

    pub fn reflect(
        wo: Vec4f,
        n_dot_wo: f32,
        alpha: Vec2f,
        xi: Vec2f,
        fresnel: anytype,
        layer: Layer,
        result: *bxdf.Sample,
    ) f32 {
        if (alpha[0] == alpha[1]) {
            return Iso.reflect(wo, n_dot_wo, alpha[0], xi, fresnel, layer, result);
        }

        var n_dot_h: f32 = undefined;
        const h = sample(wo, alpha, xi, layer, &n_dot_h);

        const x_dot_h = math.dot3(layer.t, h);
        const y_dot_h = math.dot3(layer.b, h);

        const wo_dot_h = hlp.clampDot(wo, h);

        const wi = math.normalize3(@splat(4, 2.0 * wo_dot_h) * h - wo);

        const n_dot_wi = layer.clampNdot(wi);

        const d = distribution(n_dot_h, x_dot_h, y_dot_h, alpha);

        const t_dot_wi = math.dot3(layer.t, wi);
        const t_dot_wo = math.dot3(layer.t, wo);
        const b_dot_wi = math.dot3(layer.b, wi);
        const b_dot_wo = math.dot3(layer.b, wo);

        const g = visibilityAndG1Wo(t_dot_wi, t_dot_wo, b_dot_wi, b_dot_wo, n_dot_wi, n_dot_wo, alpha);

        const f = fresnel.f(wo_dot_h);

        result.reflection = @splat(4, d * g[0]) * f;
        result.wi = wi;
        result.h = h;
        result.pdf = pdfVisible(d, g[1]);
        result.h_dot_wi = wo_dot_h;
        result.typef.clearWith(.Glossy_reflection);

        // SOFT_ASSERT(testing::check(result, wo, layer));

        return n_dot_wi;
    }

    pub fn sample(wo: Vec4f, alpha: Vec2f, xi: Vec2f, layer: Layer, n_dot_h: *f32) Vec4f {
        const lwo = layer.worldToTangent(wo);

        // stretch view
        const v = math.normalize3(.{ alpha[0] * lwo[0], alpha[1] * lwo[1], lwo[2], 0.0 });

        // orthonormal basis
        const cross_v_z = math.normalize3(.{ v[1], -v[0], 0.0, 0.0 }); // == cross(v, [0, 0, 1])

        const t1 = if (v[2] < 0.9999) cross_v_z else Vec4f{ 1.0, 0.0, 0.0, 0.0 };
        const t2 = Vec4f{ t1[1] * v[2], -t1[0] * v[2], t1[0] * v[1] - t1[1] * v[0], 0.0 };

        // sample point with polar coordinates (r, phi)
        const a = 1.0 / (1.0 + v[2]);
        const r = @sqrt(xi[0]);
        const phi = if (xi[1] < a) (xi[1] / a * std.math.pi) else (std.math.pi + (xi[1] - a) / (1.0 - a) * std.math.pi);

        const sin_phi = @sin(phi);
        const cos_phi = @cos(phi);

        const p1 = r * cos_phi;
        const p2 = r * sin_phi * (if (xi[1] < a) 1.0 else v[2]);

        // compute normal
        var m = @splat(4, p1) * t1 + @splat(4, p2) * t2 + @splat(4, @sqrt(std.math.max(1.0 - p1 * p1 - p2 * p2, 0.0))) * v;

        // unstretch
        m = math.normalize3(.{ alpha[0] * m[0], alpha[1] * m[1], std.math.max(m[2], 0.0), 0.0 });

        n_dot_h.* = hlp.clamp(m[2]);

        const h = layer.tangentToWorld(m);

        return h;
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
