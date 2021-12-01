const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Interpolation = int.Interpolation;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const Worker = @import("../worker.zig").Worker;
const Filter = @import("../../image/texture/sampler.zig").Filter;
const ro = @import("../ray_offset.zig");

const base = @import("base");
const RNG = base.rnd.Generator;
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const Cube = struct {
    pub fn intersect(ray: *Ray, trafo: Transformation, ipo: Interpolation, isec: *Intersection) bool {
        const local_origin = trafo.worldToObjectPoint(ray.origin);
        const local_dir = trafo.worldToObjectVector(ray.direction);

        const local_ray = Ray.init(local_origin, local_dir, ray.minT(), ray.maxT());

        const aabb = AABB.init(@splat(4, @as(f32, -1.0)), @splat(4, @as(f32, 1.0)));

        const hit_t = aabb.intersectP(local_ray) orelse return false;

        ray.setMaxT(hit_t);

        isec.p = ray.point(hit_t);

        const local_p = local_ray.point(hit_t);
        const distance = @fabs(@splat(4, @as(f32, 1.0)) - @fabs(local_p));

        const i = math.indexMinComponent3(distance);
        const s = std.math.copysign(f32, 1.0, local_p[i]);
        const n = @splat(4, s) * trafo.rotation.r[i];

        isec.part = 0;
        isec.primitive = 0;
        isec.geo_n = n;
        isec.n = n;

        if (.Normal != ipo) {
            const tb = math.orthonormalBasis3(n);
            isec.t = tb[0];
            isec.b = tb[1];
        }

        return true;
    }

    pub fn intersectP(ray: Ray, trafo: Transformation) bool {
        const local_origin = trafo.worldToObjectPoint(ray.origin);
        const local_dir = trafo.worldToObjectVector(ray.direction);

        const local_ray = Ray.init(local_origin, local_dir, ray.minT(), ray.maxT());

        const aabb = AABB.init(@splat(4, @as(f32, -1.0)), @splat(4, @as(f32, 1.0)));

        return aabb.intersect(local_ray);
    }

    pub fn visibility(ray: Ray, trafo: Transformation, entity: usize, filter: ?Filter, worker: Worker) ?Vec4f {
        _ = ray;
        _ = trafo;
        _ = entity;
        _ = filter;
        _ = worker;

        return @splat(4, @as(f32, 1.0));
    }
};
