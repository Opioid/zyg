const scn = @import("../../../scene/ray.zig");
const Trafo = @import("../../../scene/composed_transformation.zig").ComposedTransformation;
const intr = @import("../../../scene/prop/interface.zig");
const Interface = intr.Interface;
const Stack = intr.Stack;
const Result = @import("result.zig").Result;
const Worker = @import("../../../rendering/worker.zig").Worker;
const Filter = @import("../../../image/texture/texture_sampler.zig").Filter;
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
pub const Abort_epsilon4 = Vec4f{ Abort_epsilon, Abort_epsilon, Abort_epsilon, std.math.f32_max };

pub fn propTransmittance(
    ray: Ray,
    trafo: Trafo,
    material: *const Material,
    prop: u32,
    depth: u32,
    filter: ?Filter,
    worker: *Worker,
) ?Vec4f {
    const d = ray.maxT();

    if (ro.offsetF(ray.minT()) >= d) {
        return @splat(4, @as(f32, 1.0));
    }

    if (material.heterogeneousVolume()) {
        return transmittanceHetero(ray, trafo, material, prop, depth, filter, worker);
    }

    const cc = material.collisionCoefficients2D(@splat(2, @as(f32, 0.0)), filter, worker.scene);
    const mu_t = cc.a + cc.s;
    return hlp.attenuation3(mu_t, d - ray.minT());
}

pub fn transmittance(ray: scn.Ray, stack: *const Stack, filter: ?Filter, worker: *Worker) ?Vec4f {
    const d = ray.ray.maxT();

    if (ro.offsetF(ray.ray.minT()) >= d) {
        return @splat(4, @as(f32, 1.0));
    }

    var w = @splat(4, @as(f32, 1.0));
    var mu_t = @splat(4, @as(f32, 0.0));

    const depth = ray.depth;

    const n = stack.countUntilBorder(worker.scene);
    for (0..n) |i| {
        const interface = stack.top(@intCast(u32, i));
        const material = interface.material(worker.scene);

        if (material.heterogeneousVolume()) {
            const trafo = worker.scene.propTransformationAt(interface.prop, ray.time);

            if (transmittanceHetero(ray.ray, trafo, material, interface.prop, depth, filter, worker)) |tr| {
                w *= tr;
            } else {
                return null;
            }
        } else {
            const mu = interface.cc;
            mu_t += mu.a + mu.s;
        }
    }

    return w * hlp.attenuation3(mu_t, d - ray.ray.minT());
}

fn transmittanceHetero(ray: Ray, trafo: Trafo, material: *const Material, prop: u32, depth: u32, filter: ?Filter, worker: *Worker) ?Vec4f {
    if (material.volumetricTree()) |tree| {
        const d = ray.maxT();

        var local_ray = texturespaceRay(ray, trafo, prop, worker);

        const srs = material.super().similarityRelationScale(depth);

        var w = @splat(4, @as(f32, 1.0));
        while (local_ray.minT() < d) {
            if (tree.intersect(&local_ray)) |tcm| {
                var cm = tcm;
                cm.minorant_mu_s *= srs;
                cm.majorant_mu_s *= srs;

                if (!trackingTransmitted(&w, local_ray, cm, material, srs, filter, worker)) {
                    return null;
                }
            }

            local_ray.setMinMaxT(ro.offsetF(local_ray.maxT()), d);
        }

        return w;
    }

    return null;
}

fn trackingTransmitted(
    transmitted: *Vec4f,
    ray: Ray,
    cm: CM,
    material: *const Material,
    srs: f32,
    filter: ?Filter,
    worker: *Worker,
) bool {
    const mt = cm.majorant_mu_t();

    if (mt < Min_mt) {
        return true;
    }

    const minorant_mu_t = cm.minorant_mu_t();
    if (minorant_mu_t > 0.0) {
        return residualRatioTrackingTransmitted(
            transmitted,
            ray,
            minorant_mu_t,
            mt,
            material,
            srs,
            filter,
            worker,
        );
    }

    var rng = &worker.rng;

    const d = ray.maxT();
    var t = ray.minT();
    while (true) {
        const r0 = rng.randomFloat();
        t -= @log(1.0 - r0) / mt;
        if (t > d) {
            return true;
        }

        const uvw = ray.point(t);

        var mu = material.collisionCoefficients3D(uvw, filter, worker.scene);
        mu.s *= @splat(4, srs);

        const mu_t = mu.a + mu.s;
        const mu_n = @splat(4, mt) - mu_t;

        transmitted.* *= mu_n / @splat(4, mt);

        if (math.allLess4(transmitted.*, Abort_epsilon4)) {
            return false;
        }
    }
}

// Code for hetereogeneous transmittance inspired by:
// https://github.com/DaWelter/ToyTrace/blob/master/src/atmosphere.cxx

fn residualRatioTrackingTransmitted(
    transmitted: *Vec4f,
    ray: Ray,
    minorant_mu_t: f32,
    majorant_mu_t: f32,
    material: *const Material,
    srs: f32,
    filter: ?Filter,
    worker: *Worker,
) bool {
    // Transmittance of the control medium
    transmitted.* *= @splat(4, hlp.attenuation1(ray.maxT() - ray.minT(), minorant_mu_t));

    if (math.allLess4(transmitted.*, Abort_epsilon4)) {
        return false;
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

        var mu = material.collisionCoefficients3D(uvw, filter, worker.scene);
        mu.s *= @splat(4, srs);

        const mu_t = (mu.a + mu.s) - @splat(4, minorant_mu_t);
        const mu_n = @splat(4, mt) - mu_t;

        transmitted.* *= mu_n / @splat(4, mt);

        if (math.allLess4(transmitted.*, Abort_epsilon4)) {
            return false;
        }
    }
}

pub fn tracking(ray: Ray, mu: CC, throughput: Vec4f, sampler: *Sampler) Result {
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
            return Result.initPass(w);
        }

        const wt = w * throughput;
        const ms = math.average3(mu.s * wt);
        const mn = math.average3(mu_n * wt);
        const mc = ms + mn;
        if (mc < 1.0e-10) {
            return Result.initPass(w);
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

pub fn trackingEmission(ray: Ray, cce: CCE, throughput: Vec4f, rng: *RNG) Result {
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
            return Result.initPass(w);
        }

        const wt = w * throughput;
        const ma = math.average3(mu.a * wt);
        const ms = math.average3(mu.s * wt);
        const mn = math.average3(mu_n * wt);
        const mc = ma + ms + mn;
        if (mc < 1.0e-10) {
            return Result.initPass(w);
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
                .tr = @splat(4, @as(f32, 0.0)),
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
    filter: ?Filter,
    worker: *Worker,
) Result {
    const mt = cm.majorant_mu_t();
    if (mt < Min_mt) {
        return Result.initPass(w);
    }

    var rng = &worker.rng;

    var lw = w;

    const d = ray.maxT();
    var t = ray.minT();
    while (true) {
        const r0 = rng.randomFloat();
        t -= @log(1.0 - r0) / mt;
        if (t > d) {
            return Result.initPass(lw);
        }

        const uvw = ray.point(t);

        var mu = material.collisionCoefficients3D(uvw, filter, worker.scene);
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
    filter: ?Filter,
    worker: *Worker,
) Result {
    const mt = cm.majorant_mu_t();
    if (mt < Min_mt) {
        return Result.initPass(w);
    }

    var rng = &worker.rng;

    var lw = w;

    const d = ray.maxT();
    var t = ray.minT();
    while (true) {
        const r0 = rng.randomFloat();
        t -= @log(1.0 - r0) / mt;
        if (t > d) {
            return Result.initPass(lw);
        }

        const uvw = ray.point(t);

        const cce = material.collisionCoefficientsEmission(uvw, filter, worker.scene);
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
                .tr = @splat(4, @as(f32, 0.0)),
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

pub fn texturespaceRay(ray: Ray, trafo: Trafo, entity: u32, worker: *const Worker) Ray {
    const local_origin = trafo.worldToObjectPoint(ray.origin);
    const local_dir = trafo.worldToObjectVector(ray.direction);

    const aabb = worker.scene.propShape(entity).aabb();

    const iextent = @splat(4, @as(f32, 1.0)) / aabb.extent();
    const origin = (local_origin - aabb.bounds[0]) * iextent;
    const dir = local_dir * iextent;

    return Ray.init(origin, dir, ray.minT(), ray.maxT());
}
