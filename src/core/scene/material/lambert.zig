const bxdf = @import("bxdf.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Layer = @import("sample_base.zig").Layer;
const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

pub fn reflect(color: Vec4f, layer: Layer, sampler: *Sampler, rng: *RNG, result: *bxdf.Sample) f32 {
    const s2d = sampler.sample2D(rng, 0);
    const is = math.smpl.hemisphereCosine(s2d);
    const wi = math.normalize3(layer.tangentToWorld(is));

    const n_dot_wi = layer.clampNdot(wi);

    result.reflection = @splat(4, @as(f32, math.pi_inv)) * color;
    result.wi = wi;
    result.pdf = n_dot_wi * math.pi_inv;
    result.typef.clearWith(.DiffuseReflection);

    return n_dot_wi;
}
