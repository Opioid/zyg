const bxdf = @import("bxdf.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const ggx = @import("ggx.zig");
const integral = @import("ggx_integral.zig");

const base = @import("base");
const math = base.math;
const Frame = math.Frame;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Lambert = struct {
    pub fn reflect(color: Vec4f, frame: Frame, sampler: *Sampler, result: *bxdf.Sample) f32 {
        const s2d = sampler.sample2D();
        const is = math.smpl.hemisphereCosine(s2d);
        const wi = math.normalize3(frame.frameToWorld(is));

        const n_dot_wi = frame.clampNdot(wi);

        result.reflection = @as(Vec4f, @splat(@as(f32, math.pi_inv))) * color;
        result.wi = wi;
        result.pdf = n_dot_wi * math.pi_inv;
        result.class = .{ .diffuse = true, .reflection = true };

        return n_dot_wi;
    }
};

const E_tex = math.ifunc.InterpolatedFunction3DN(
    integral.E_size,
    integral.E_size,
    integral.E_size,
).fromArray(&integral.E);

const E_avg_tex = math.ifunc.InterpolatedFunction2DN(
    integral.E_avg_size,
    integral.E_avg_size,
).fromArray(&integral.E_avg);

pub const Micro = struct {
    pub fn estimateContribution(n_dot_wo: f32, alpha: f32, f0: f32, albedo: f32) f32 {
        //     const e_wo = E_tex.eval(n_dot_wo, alpha, f0);
        //     const e_avg = E_avg_tex.eval(alpha, f0);

        //     const a = e_wo; // * e_avg;
        //    // const b: f32 = ((1.0 - e_wo) / std.math.pi * (1.0 - e_avg)) * albedo;
        //       const b: f32 = (1.0 / std.math.pi * (1.0 - e_avg)) * albedo;
        //     return b / (a + b);

        // Good candidate A
        // const e_wo = E_tex.eval(n_dot_wo, alpha, f0);
        // const e_avg = E_avg_tex.eval(alpha, f0);

        // const a = e_wo;
        // const b: f32 = 1.0 / (std.math.pi * (1.0 - e_avg)) * albedo;
        // return b / (a + b);

        // Good candidate B
        _ = n_dot_wo;
        const e_avg = E_avg_tex.eval(alpha, f0);

        const a = e_avg;
        const b: f32 = 1.0 / (std.math.pi * (1.0 - e_avg)) * albedo;
        return b / (a + b);

        // _ = n_dot_wo;
        // _ = alpha;
        // _ = f0;
        // _ = albedo;

        // return 0.5;
    }

    pub fn reflection(color: Vec4f, f0: f32, n_dot_wi: f32, n_dot_wo: f32, alpha: f32) bxdf.Result {
        const refl = evaluate(color, n_dot_wi, n_dot_wo, alpha, f0);

        const pdf = n_dot_wi * math.pi_inv;

        return bxdf.Result.init(refl, pdf);
    }

    pub fn reflect(
        color: Vec4f,
        f0: f32,
        wo: Vec4f,
        n_dot_wo: f32,
        frame: Frame,
        alpha: f32,
        xi: Vec2f,
        result: *bxdf.Sample,
    ) ggx.Micro {
        const is = math.smpl.hemisphereCosine(xi);
        const wi = math.normalize3(frame.frameToWorld(is));
        const h = math.normalize3(wo + wi);

        const h_dot_wi = math.safe.clampDot(h, wi);
        const n_dot_wi = frame.clampNdot(wi);

        result.reflection = evaluate(color, n_dot_wi, n_dot_wo, alpha, f0);
        result.wi = wi;
        result.pdf = n_dot_wi * math.pi_inv;
        result.class = .{ .diffuse = true, .reflection = true };

        return .{ .h = h, .n_dot_wi = n_dot_wi, .h_dot_wi = h_dot_wi };
    }

    fn evaluate(color: Vec4f, n_dot_wi: f32, n_dot_wo: f32, alpha: f32, f0: f32) Vec4f {
        const e_wo = E_tex.eval(n_dot_wo, alpha, f0);
        const e_wi = E_tex.eval(n_dot_wi, alpha, f0);
        const e_avg = E_avg_tex.eval(alpha, f0);

        return @as(Vec4f, @splat(((1.0 - e_wo) * (1.0 - e_wi)) / (std.math.pi * (1.0 - e_avg)))) * color;
    }
};
