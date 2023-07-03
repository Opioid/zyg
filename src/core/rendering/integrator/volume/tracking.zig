const Trafo = @import("../../../scene/composed_transformation.zig").ComposedTransformation;
const intr = @import("../../../scene/prop/interface.zig");
const Interface = intr.Interface;
const Stack = intr.Stack;
const Volume = @import("../../../scene/shape/intersection.zig").Volume;
const Worker = @import("../../../rendering/worker.zig").Worker;
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
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");

const Min_mt = 1.0e-10;
const Abort_epsilon = 7.5e-4;
pub const Abort_epsilon4 = Vec4f{ Abort_epsilon, Abort_epsilon, Abort_epsilon, std.math.floatMax(f32) };

pub fn transmittanceHetero(
    ray: Ray,
    material: *const Material,
    prop: u32,
    depth: u32,
    sampler: *Sampler,
    worker: *Worker,
) ?Vec4f {
    if (material.volumetricTree()) |tree| {
        const d = ray.maxT();

        var local_ray = objectToTextureRay(ray, prop, worker);

        const srs = material.super().similarityRelationScale(depth);

        var w = @splat(4, @as(f32, 1.0));
        while (local_ray.minT() < d) {
            if (tree.intersect(&local_ray)) |cm| {
                if (!trackingTransmitted(&w, local_ray, cm, material, srs, sampler, worker)) {
                    return null;
                }
            }

            local_ray.setMinMaxT(ro.offsetF(local_ray.maxT()), d);
        }

        return w;
    }

    return null;
}

// Code for (residual ratio) hetereogeneous transmittance inspired by:
// https://github.com/DaWelter/ToyTrace/blob/master/src/atmosphere.cxx

fn trackingTransmitted(
    transmitted: *Vec4f,
    ray: Ray,
    cm: CM,
    material: *const Material,
    srs: f32,
    sampler: *Sampler,
    worker: *Worker,
) bool {
    const minorant_mu_t = cm.minorant_mu_t(srs);
    const majorant_mu_t = cm.majorant_mu_t(srs);

    if (minorant_mu_t > 0.0) {
        // Transmittance of the control medium
        transmitted.* *= @splat(4, hlp.attenuation1(ray.maxT() - ray.minT(), minorant_mu_t));

        if (math.allLess4(transmitted.*, Abort_epsilon4)) {
            return false;
        }
    }

    const mt = majorant_mu_t - minorant_mu_t;

    if (mt < Min_mt) {
        return true;
    }

    var rng = &worker.rng;

    // Transmittance of the residual medium
    const d = ray.maxT();
    var t = ray.minT();
    while (true) {
        const r0 = rng.randomFloat();
        t -= @log(1.0 - r0) / mt;
        if (t > d) {
            return true;
        }

        const uvw = ray.point(t);
        var mu = material.collisionCoefficients3D(uvw, sampler, worker.scene);
        mu.s *= @splat(4, srs);

        const mu_t = (mu.a + mu.s) - @splat(4, minorant_mu_t);
        const mu_n = @splat(4, mt) - mu_t;

        transmitted.* *= mu_n / @splat(4, mt);

        if (math.allLess4(transmitted.*, Abort_epsilon4)) {
            return false;
        }
    }
}

pub fn tracking(ray: Ray, mu: CC, throughput: Vec4f, sampler: *Sampler) Volume {
    const mu_t = mu.a + mu.s;
    const mt = math.hmax3(mu_t);
    const mu_n = @splat(4, mt) - mu_t;

    var w = @splat(4, @as(f32, 1.0));

    const d = ray.maxT();
    var t = ray.minT();
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
            const ws = mu.s / @splat(4, mt * ps);
            return .{
                .li = @splat(4, @as(f32, 0.0)),
                .tr = w * ws,
                .t = t,
                .event = .Scatter,
            };
        }

        const wn = mu_n / @splat(4, mt * pn);
        w *= wn;
    }
}

pub fn trackingEmission(ray: Ray, cce: CCE, throughput: Vec4f, rng: *RNG) Volume {
    const mu = cce.cc;
    const mu_t = mu.a + mu.s;
    const mt = math.hmax3(mu_t);
    const mu_n = @splat(4, mt) - mu_t;

    var w = @splat(4, @as(f32, 1.0));

    const d = ray.maxT();
    var t = ray.minT();
    while (true) {
        const r0 = rng.randomFloat();
        t -= @log(1.0 - r0) / mt;
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

        const r1 = rng.randomFloat();
        if (r1 < pa) {
            const wa = mu.a / @splat(4, mt * pa);
            return .{
                .li = w * wa * cce.e,
                .tr = @splat(4, @as(f32, 1.0)),
                .t = t,
                .event = .Absorb,
            };
        }

        if (r1 <= 1.0 - pn and ps > 0.0) {
            const ws = mu.s / @splat(4, mt * ps);
            return .{
                .li = @splat(4, @as(f32, 0.0)),
                .tr = w * ws,
                .t = t,
                .event = .Scatter,
            };
        }

        const wn = mu_n / @splat(4, mt * pn);
        w *= wn;
    }
}

pub fn trackingHetero(
    ray: Ray,
    cm: CM,
    material: *const Material,
    srs: f32,
    w: Vec4f,
    throughput: Vec4f,
    sampler: *Sampler,
    worker: *Worker,
) Volume {
    const mt = cm.majorant_mu_t(srs);
    if (mt < Min_mt) {
        return Volume.initPass(w);
    }

    var rng = &worker.rng;

    var lw = w;

    const d = ray.maxT();
    var t = ray.minT();
    while (true) {
        const r0 = rng.randomFloat();
        t -= @log(1.0 - r0) / mt;
        if (t > d) {
            return Volume.initPass(lw);
        }

        const uvw = ray.point(t);
        var mu = material.collisionCoefficients3D(uvw, sampler, worker.scene);
        mu.s *= @splat(4, srs);

        const mu_t = mu.a + mu.s;
        const mu_n = @splat(4, mt) - mu_t;

        const wt = lw * throughput;
        const ms = math.average3(mu.s * wt);
        const mn = math.average3(mu_n * wt);

        const c = 1.0 / (ms + mn);
        const ps = ms * c;
        const pn = mn * c;

        const r1 = rng.randomFloat();
        if (r1 <= 1.0 - pn and ps > 0.0) {
            const ws = mu.s / @splat(4, mt * ps);
            return .{
                .li = @splat(4, @as(f32, 0.0)),
                .tr = lw * ws,
                .t = t,
                .event = .Scatter,
            };
        }

        const wn = mu_n / @splat(4, mt * pn);
        lw *= wn;
    }
}

pub fn trackingHeteroEmission(
    ray: Ray,
    cm: CM,
    material: *const Material,
    srs: f32,
    w: Vec4f,
    throughput: Vec4f,
    sampler: *Sampler,
    worker: *Worker,
) Volume {
    const mt = cm.majorant_mu_t(srs);
    if (mt < Min_mt) {
        return Volume.initPass(w);
    }

    var rng = &worker.rng;

    var lw = w;

    const d = ray.maxT();
    var t = ray.minT();
    while (true) {
        const r0 = rng.randomFloat();
        t -= @log(1.0 - r0) / mt;
        if (t > d) {
            return Volume.initPass(lw);
        }

        const uvw = ray.point(t);
        const cce = material.collisionCoefficientsEmission(uvw, sampler, worker.scene);
        var mu = cce.cc;
        mu.s *= @splat(4, srs);

        const mu_t = mu.a + mu.s;
        const mu_n = @splat(4, mt) - mu_t;

        const wt = lw * throughput;
        const ma = math.average3(mu.a * wt);
        const ms = math.average3(mu.s * wt);
        const mn = math.average3(mu_n * wt);

        const c = 1.0 / (ma + ms + mn);
        const pa = ma * c;
        const ps = ms * c;
        const pn = mn * c;

        const r1 = rng.randomFloat();
        if (r1 < pa) {
            const wa = mu.a / @splat(4, mt * pa);
            return .{
                .li = w * wa * cce.e,
                .tr = @splat(4, @as(f32, 1.0)),
                .t = t,
                .event = .Absorb,
            };
        }

        if (r1 <= 1.0 - pn and ps > 0.0) {
            const ws = mu.s / @splat(4, mt * ps);
            return .{
                .li = @splat(4, @as(f32, 0.0)),
                .tr = lw * ws,
                .t = t,
                .event = .Scatter,
            };
        }

        const wn = mu_n / @splat(4, mt * pn);
        lw *= wn;
    }
}

pub fn objectToTextureRay(ray: Ray, entity: u32, worker: *const Worker) Ray {
    const aabb = worker.scene.propShape(entity).aabb();

    const iextent = @splat(4, @as(f32, 1.0)) / aabb.extent();
    const origin = (ray.origin - aabb.bounds[0]) * iextent;
    const dir = ray.direction * iextent;

    return Ray.init(origin, dir, ray.minT(), ray.maxT());
}
