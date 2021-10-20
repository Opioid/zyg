const scn = @import("../../../scene/ray.zig");
const Result = @import("result.zig").Result;
const Worker = @import("../../../scene/worker.zig").Worker;
const Filter = @import("../../../image/texture/sampler.zig").Filter;
const hlp = @import("../../../rendering/integrator/helper.zig");
const ro = @import("../../../scene/ray_offset.zig");
const ccoef = @import("../../../scene/material/collision_coefficients.zig");
const CC = ccoef.CC;
const base = @import("base");
const math = base.math;
const Ray = math.Ray;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

pub fn transmittance(ray: scn.Ray, filter: ?Filter, worker: *Worker) ?Vec4f {
    _ = filter;

    const interface = worker.interface_stack.top();
    const material = interface.material(worker.*);

    const d = ray.ray.maxT();

    if (ro.offsetF(ray.ray.minT()) >= d) {
        return @splat(4, @as(f32, 1.0));
    }

    const mu = material.super().cc;
    const mu_t = mu.a + mu.s;

    return hlp.attenuation3(mu_t, d - ray.ray.minT());
}

pub fn tracking(ray: Ray, mu: CC, rng: *RNG) Result {
    const mu_t = mu.a + mu.s;

    const mt = math.maxComponent3(mu_t);
    const imt = 1.0 / mt;

    const mu_n = @splat(4, mt) - mu_t;

    var w = @splat(4, @as(f32, 1.0));

    var t = ray.minT();
    const d = ray.maxT();
    while (true) {
        const r0 = rng.randomFloat();
        t -= @log(1.0 - r0) * imt;
        if (t > d) {
            return Result{
                .li = @splat(4, @as(f32, 0.0)),
                .tr = w,
                .event = .Pass,
            };
        }

        const ms = math.average3(mu.s * w);
        const mn = math.average3(mu_n * w);

        const mc = ms + mn;
        if (mc < 1.0e-10) {
            return Result{
                .li = @splat(4, @as(f32, 0.0)),
                .tr = w,
                .event = .Pass,
            };
        }

        const c = 1.0 / mc;

        const ps = ms * c;
        const pn = mn * c;

        const r1 = rng.randomFloat();
        if (r1 <= 1.0 - pn and ps > 0.0) {
            const ws = mu.s / @splat(4, mt * ps);
            return Result{
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

pub fn texturespaceRay(ray: scn.Ray, entity: u32, worker: Worker) Ray {
    const trafo = worker.scene.propTransformationAt(entity, ray.time);

    const local_origin = trafo.worldToObjectPoint(ray.ray.origin);
    const local_dir = trafo.worldToObjectVector(ray.ray.direction);

    const shape_inst = worker.scene().prop_shape(entity);

    const aabb = shape_inst.aabb();

    const iextent = @splat(4, @as(f32, 1.0)) / aabb.extent();
    const origin = (local_origin - aabb.bounds[0]) * iextent;
    const dir = local_dir * iextent;

    return Ray.init(origin, dir, ray.ray.minT(), ray.ray.maxT());
}
