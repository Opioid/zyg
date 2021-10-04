const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const SampleTo = @import("sample.zig").To;
const Worker = @import("../worker.zig").Worker;
const Filter = @import("../../image/texture/sampler.zig").Filter;
const ro = @import("../ray_offset.zig");
const Dot_min = @import("../material/sample_helper.zig").Dot_min;

const base = @import("base");
const RNG = base.rnd.Generator;
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const Disk = struct {
    pub fn intersect(ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const l = math.dot3(k, k);
            const radius = trafo.scaleX();

            if (l <= radius * radius) {
                const t = -trafo.rotation.r[0];
                const b = -trafo.rotation.r[1];

                const sk = k / @splat(4, radius);
                const uv_scale = 0.5 * trafo.scaleZ();

                isec.p = p;
                isec.t = t;
                isec.b = b;
                isec.n = normal;
                isec.geo_n = normal;
                isec.uv = .{
                    (math.dot3(t, sk) + 1.0) * uv_scale,
                    (math.dot3(b, sk) + 1.0) * uv_scale,
                };
                isec.part = 0;

                ray.setMaxT(hit_t);
                return true;
            }
        }

        return false;
    }

    pub fn intersectP(ray: Ray, trafo: Transformation) bool {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const l = math.dot3(k, k);
            const radius = trafo.scaleX();

            if (l <= radius * radius) {
                return true;
            }
        }

        return false;
    }

    pub fn visibility(
        ray: Ray,
        trafo: Transformation,
        entity: usize,
        filter: ?Filter,
        worker: Worker,
    ) ?Vec4f {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const l = math.dot3(k, k);
            const radius = trafo.scaleX();

            if (l <= radius * radius) {
                const t = -trafo.rotation.r[0];
                const b = -trafo.rotation.r[1];

                const sk = k / @splat(4, radius);
                const uv_scale = 0.5 * trafo.scaleZ();

                const uv = Vec2f{
                    (math.dot3(t, sk) + 1.0) * uv_scale,
                    (math.dot3(b, sk) + 1.0) * uv_scale,
                };

                return worker.scene.propMaterial(entity, 0).visibility(uv, filter, worker);
            }
        }

        return @splat(4, @as(f32, 1.0));
    }
};