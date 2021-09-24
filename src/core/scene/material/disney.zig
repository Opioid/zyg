const bxdf = @import("bxdf.zig");
const Layer = @import("sample_base.zig").Layer;
const hlp = @import("sample_helper.zig");
const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Iso = struct {
    pub fn reflection(
        h_dot_wi: f32,
        n_dot_wi: f32,
        n_dot_wo: f32,
        alpha: f32,
        color: Vec4f,
    ) bxdf.Result {
        const refl = evaluate(h_dot_wi, n_dot_wi, n_dot_wo, alpha, color);

        const pdf = n_dot_wi * math.pi_inv;

        return bxdf.Result.init(refl, pdf);
    }

    pub fn reflect(
        wo: Vec4f,
        n_dot_wo: f32,
        layer: Layer,
        alpha: f32,
        color: Vec4f,
        xi: Vec2f,
        result: *bxdf.Sample,
    ) f32 {
        const is = math.smpl.hemisphereCosine(xi);
        const wi = math.normalize3(layer.tangentToWorld(is));
        const h = math.normalize3(wo + wi);

        const h_dot_wi = hlp.clampDot(h, wi);
        const n_dot_wi = layer.clampNdot(wi);

        result.reflection = evaluate(h_dot_wi, n_dot_wi, n_dot_wo, alpha, color);
        result.wi = wi;
        result.h = h;
        result.pdf = n_dot_wi * math.pi_inv;
        result.h_dot_wi = h_dot_wi;
        result.typef.clearWith(.Diffuse_reflection);

        return n_dot_wi;
    }

    fn evaluate(h_dot_wi: f32, n_dot_wi: f32, n_dot_wo: f32, alpha: f32, color: Vec4f) Vec4f {
        const energy_bias = math.lerp(0.0, 0.5, alpha);
        const energy_factor = math.lerp(1.0, 1.0 / 1.53, alpha);

        const f_D90 = energy_bias + (2.0 * alpha) * (h_dot_wi * h_dot_wi);
        const fmo = f_D90 - 1.0;

        const a = 1.0 + fmo * math.pow5(1.0 - n_dot_wi);
        const b = 1.0 + fmo * math.pow5(1 - n_dot_wo);

        return @splat(4, a * b * energy_factor * math.pi_inv) * color;
    }
};
