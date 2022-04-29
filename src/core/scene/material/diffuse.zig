const bxdf = @import("bxdf.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Layer = @import("sample_base.zig").Layer;
const hlp = @import("sample_helper.zig");
const integral = @import("ggx_integral.zig");

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");

pub const Lambert = struct {
    pub fn reflect(color: Vec4f, layer: Layer, sampler: *Sampler, rng: *RNG, result: *bxdf.Sample) f32 {
        const s2d = sampler.sample2D(rng);
        const is = math.smpl.hemisphereCosine(s2d);
        const wi = math.normalize3(layer.tangentToWorld(is));

        const n_dot_wi = layer.clampNdot(wi);

        result.reflection = @splat(4, @as(f32, math.pi_inv)) * color;
        result.wi = wi;
        result.pdf = n_dot_wi * math.pi_inv;
        result.class.clearWith(.DiffuseReflection);

        return n_dot_wi;
    }
};

const E_tex = math.InterpolatedFunction3D_N(
    integral.E_size,
    integral.E_size,
    integral.E_size,
).fromArray(&integral.E);

const E_avg_tex = math.InterpolatedFunction2D_N(
    integral.E_avg_size,
    integral.E_avg_size,
).fromArray(&integral.E_avg);

pub const Micro = struct {
    pub fn reflection(
        color: Vec4f,
        f0: Vec4f,
        n_dot_wi: f32,
        n_dot_wo: f32,
        alpha: f32,
    ) bxdf.Result {
        const refl = evaluate(color, f0, n_dot_wi, n_dot_wo, alpha);

        const pdf = n_dot_wi * math.pi_inv;

        return bxdf.Result.init(refl, pdf);
    }

    pub fn reflect(
        color: Vec4f,
        f0: Vec4f,
        wo: Vec4f,
        n_dot_wo: f32,
        layer: Layer,
        alpha: f32,
        xi: Vec2f,
        result: *bxdf.Sample,
    ) f32 {
        const is = math.smpl.hemisphereCosine(xi);
        const wi = math.normalize3(layer.tangentToWorld(is));
        const h = math.normalize3(wo + wi);

        const h_dot_wi = hlp.clampDot(h, wi);
        const n_dot_wi = layer.clampNdot(wi);

        result.reflection = evaluate(color, f0, n_dot_wi, n_dot_wo, alpha);
        result.wi = wi;
        result.h = h;
        result.pdf = n_dot_wi * math.pi_inv;
        result.h_dot_wi = h_dot_wi;
        result.class.clearWith(.DiffuseReflection);

        return n_dot_wi;
    }

    fn evaluate(color: Vec4f, f0: Vec4f, n_dot_wi: f32, n_dot_wo: f32, alpha: f32) Vec4f {
        const f0m = math.maxComponent3(f0);

        const e_wo = E_tex.eval(n_dot_wo, alpha, f0m);
        const e_wi = E_tex.eval(n_dot_wi, alpha, f0m);
        const e_avg = E_avg_tex.eval(alpha, f0m);

        return @splat(4, ((1.0 - e_wo) * (1.0 - e_wi)) / (std.math.pi * (1.0 - e_avg))) * color;
    }
};
