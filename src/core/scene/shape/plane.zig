const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const Worker = @import("../worker.zig").Worker;
const Filter = @import("../../image/texture/sampler.zig").Filter;
const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

pub const Plane = struct {
    pub fn intersect(ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];
            const b = -trafo.rotation.r[1];

            isec.p = p;
            isec.geo_n = n;
            isec.t = t;
            isec.b = b;
            isec.n = n;
            isec.uv = Vec2f.init2(math.dot3(t, k), math.dot3(b, k));
            isec.part = 0;

            ray.setMaxT(hit_t);
            return true;
        }

        return false;
    }

    pub fn intersectP(ray: Ray, trafo: Transformation) bool {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            return true;
        }

        return false;
    }

    pub fn visibility(
        ray: Ray,
        trafo: Transformation,
        entity: usize,
        filter: ?Filter,
        worker: Worker,
        vis: *Vec4f,
    ) bool {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const uv = Vec2f.init2(-math.dot3(trafo.rotation.r[0], k), -math.dot3(trafo.rotation.r[1], k));

            return worker.scene.propMaterial(entity, 0).visibility(uv, filter, worker, vis);
        }

        vis.* = @splat(4, @as(f32, 1.0));
        return true;
    }
};
