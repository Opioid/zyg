const Context = @import("../../../scene/context.zig").Context;
const Trafo = @import("../../../scene/composed_transformation.zig").ComposedTransformation;
const Volume = @import("../../../scene/shape/intersection.zig").Volume;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const hlp = @import("../../../rendering/integrator/helper.zig");
const ro = @import("../../../scene/ray_offset.zig");
const Material = @import("../../../scene/material/material.zig").Material;
const ccoef = @import("../../../scene/material/collision_coefficients.zig");
const CC = ccoef.CC;
const CCE = ccoef.CCE;
const CM = ccoef.CM;

const base = @import("base");
const math = base.math;
const Ray = math.Ray;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");

const Min_mt = 1.0e-10;
const Abort_epsilon = 7.5e-4;
pub const Abort_epsilon4 = Vec4f{ Abort_epsilon, Abort_epsilon, Abort_epsilon, std.math.floatMax(f32) };

// Code for (residual ratio) hetereogeneous transmittance inspired by:
// https://github.com/DaWelter/ToyTrace/blob/master/src/atmosphere.cxx

pub fn trackingTransmitted(
    transmitted: *Vec4f,
    ray: Ray,
    cm: Vec2f,
    cc: CC,
    material: *const Material,
    sampler: *Sampler,
    context: Context,
) bool {
    const minorant_mu_t = cm[0];
    const majorant_mu_t = cm[1];

    if (minorant_mu_t > 0.0) {
        // Transmittance of the control medium
        transmitted.* *= @splat(ccoef.attenuation1(ray.max_t - ray.min_t, minorant_mu_t));

        if (math.allLess4(transmitted.*, Abort_epsilon4)) {
            return false;
        }
    }

    const mt = majorant_mu_t - minorant_mu_t;

    if (mt < Min_mt) {
        return true;
    }

    // Transmittance of the residual medium
    const d = ray.max_t;
    var t = ray.min_t;
    while (true) {
        const r0 = sampler.sample1D();
        t -= @log(1.0 - r0) / mt;
        if (t > d) {
            return true;
        }

        const uvw = ray.point(t);
        const mu = material.collisionCoefficients3D(uvw, cc, sampler, context);

        const mu_t = (mu.a + mu.s) - @as(Vec4f, @splat(minorant_mu_t));
        const mu_n = @as(Vec4f, @splat(mt)) - mu_t;

        transmitted.* *= mu_n / @as(Vec4f, @splat(mt));

        if (math.allLess4(transmitted.*, Abort_epsilon4)) {
            return false;
        }
    }
}

pub fn tracking(ray: Ray, mu: CC, throughput: Vec4f, sampler: *Sampler) Volume {
    const mu_t = mu.a + mu.s;
    const mt = math.hmax3(mu_t);
    const mu_n = @as(Vec4f, @splat(mt)) - mu_t;

    var w: Vec4f = @splat(1.0);

    const d = ray.max_t;
    var t = ray.min_t;
    while (true) {
        const r = sampler.sample2D();
        t -= @log(1.0 - r[0]) / mt;
        if (t > d) {
            return Volume.initPass(w);
        }

        const wt = w * throughput;
        const ms = math.average3(mu.s * wt);
        const mn = math.average3(mu_n * wt);
        const mc = ms + mn;
        if (mc < 1.0e-10) {
            return Volume.initPass(w);
        }

        const c = 1.0 / mc;
        const ps = ms * c;
        const pn = mn * c;

        if (r[1] <= 1.0 - pn and ps > 0.0) {
            const ws = mu.s / @as(Vec4f, @splat(mt * ps));
            return .{
                .li = @splat(0.0),
                .tr = w * ws,
                .t = t,
                .event = .Scatter,
            };
        }

        const wn = mu_n / @as(Vec4f, @splat(mt * pn));
        w *= wn;
    }
}

pub fn trackingEmission(ray: Ray, cce: CCE, throughput: Vec4f, sampler: *Sampler) Volume {
    const mu = cce.cc;
    const mu_t = mu.a + mu.s;
    const mt = math.hmax3(mu_t);
    const mu_n = @as(Vec4f, @splat(mt)) - mu_t;

    var w: Vec4f = @splat(1.0);

    const d = ray.max_t;
    var t = ray.min_t;
    while (true) {
        const r = sampler.sample2D();
        t -= @log(1.0 - r[0]) / mt;
        if (t > d) {
            return Volume.initPass(w);
        }

        const wt = w * throughput;
        const ma = math.average3(mu.a * wt);
        const ms = math.average3(mu.s * wt);
        const mn = math.average3(mu_n * wt);
        const mc = ma + ms + mn;
        if (mc < 1.0e-10) {
            return Volume.initPass(w);
        }

        const c = 1.0 / mc;
        const pa = ma * c;
        const ps = ms * c;
        const pn = mn * c;

        if (r[1] < pa) {
            const wa = mu.a / @as(Vec4f, @splat(mt * pa));
            return .{
                .li = w * wa * cce.e,
                .tr = @splat(1.0),
                .t = t,
                .event = .Absorb,
            };
        }

        if (r[1] <= 1.0 - pn and ps > 0.0) {
            const ws = mu.s / @as(Vec4f, @splat(mt * ps));
            return .{
                .li = @splat(0.0),
                .tr = w * ws,
                .t = t,
                .event = .Scatter,
            };
        }

        const wn = mu_n / @as(Vec4f, @splat(mt * pn));
        w *= wn;
    }
}

pub fn trackingHetero(
    ray: Ray,
    cm: Vec2f,
    cc: CC,
    material: *const Material,
    w: Vec4f,
    throughput: Vec4f,
    sampler: *Sampler,
    context: Context,
) Volume {
    const mt = cm[1];
    if (mt < Min_mt) {
        return Volume.initPass(w);
    }

    var lw = w;

    const d = ray.max_t;
    var t = ray.min_t;
    while (true) {
        const r = sampler.sample2D();
        t -= @log(1.0 - r[0]) / mt;
        if (t > d) {
            return Volume.initPass(lw);
        }

        const uvw = ray.point(t);
        const mu = material.collisionCoefficients3D(uvw, cc, sampler, context);

        const mu_t = mu.a + mu.s;
        const mu_n = @as(Vec4f, @splat(mt)) - mu_t;

        const wt = lw * throughput;
        const ms = math.average3(mu.s * wt);
        const mn = math.average3(mu_n * wt);

        const c = 1.0 / (ms + mn);
        const ps = ms * c;
        const pn = mn * c;

        if (r[1] <= 1.0 - pn and ps > 0.0) {
            const ws = mu.s / @as(Vec4f, @splat(mt * ps));
            return .{
                .li = @splat(0.0),
                .tr = lw * ws,
                .t = t,
                .event = .Scatter,
            };
        }

        const wn = mu_n / @as(Vec4f, @splat(mt * pn));
        lw *= wn;
    }
}

pub fn trackingHeteroEmission(
    ray: Ray,
    cm: Vec2f,
    cc: CC,
    material: *const Material,
    w: Vec4f,
    throughput: Vec4f,
    sampler: *Sampler,
    context: Context,
) Volume {
    const mt = cm[1];
    if (mt < Min_mt) {
        return Volume.initPass(w);
    }

    var lw = w;

    const d = ray.max_t;
    var t = ray.min_t;
    while (true) {
        const r = sampler.sample2D();
        t -= @log(1.0 - r[0]) / mt;
        if (t > d) {
            return Volume.initPass(lw);
        }

        const uvw = ray.point(t);
        const cce = material.collisionCoefficientsEmission(uvw, cc, sampler, context);
        const mu = cce.cc;

        const mu_t = mu.a + mu.s;
        const mu_n = @as(Vec4f, @splat(mt)) - mu_t;

        const wt = lw * throughput;
        const ma = math.average3(mu.a * wt);
        const ms = math.average3(mu.s * wt);
        const mn = math.average3(mu_n * wt);

        const c = 1.0 / (ma + ms + mn);
        const pa = ma * c;
        const ps = ms * c;
        const pn = mn * c;

        if (r[1] < pa) {
            const wa = mu.a / @as(Vec4f, @splat(mt * pa));
            return .{
                .li = w * wa * cce.e,
                .tr = @splat(1.0),
                .t = t,
                .event = .Absorb,
            };
        }

        if (r[1] <= 1.0 - pn and ps > 0.0) {
            const ws = mu.s / @as(Vec4f, @splat(mt * ps));
            return .{
                .li = @splat(0.0),
                .tr = lw * ws,
                .t = t,
                .event = .Scatter,
            };
        }

        const wn = mu_n / @as(Vec4f, @splat(mt * pn));
        lw *= wn;
    }
}

pub fn objectToTextureRay(ray: Ray, entity: u32, context: Context) Ray {
    const aabb = context.scene.propShape(entity).aabb(0);

    const iextent = @as(Vec4f, @splat(1.0)) / aabb.extent();
    const origin = (ray.origin - aabb.bounds[0]) * iextent;
    const dir = ray.direction * iextent;

    return Ray.init(origin, dir, ray.min_t, ray.max_t);
}
