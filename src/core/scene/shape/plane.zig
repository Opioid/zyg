const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const Worker = @import("../worker.zig").Worker;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

pub const Plane = struct {
    pub fn intersect(ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        const n = trafo.rotation.r[2];
        const d = n.dot3(trafo.position);
        const hit_t = -(n.dot3(ray.origin) - d) / n.dot3(ray.direction);

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p.sub3(trafo.position);
            const t = trafo.rotation.r[0].neg3();
            const b = trafo.rotation.r[1].neg3();

            isec.p = p;
            isec.geo_n = n;
            isec.t = t;
            isec.b = b;
            isec.n = n;
            isec.uv = Vec2f.init2(t.dot3(k), b.dot3(k));
            isec.part = 0;

            ray.setMaxT(hit_t);
            return true;
        }

        return false;
    }

    pub fn intersectP(ray: Ray, trafo: Transformation) bool {
        const n = trafo.rotation.r[2];
        const d = n.dot3(trafo.position);
        const hit_t = -(n.dot3(ray.origin) - d) / n.dot3(ray.direction);

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            return true;
        }

        return false;
    }

    pub fn visibility(ray: Ray, trafo: Transformation, entity: usize, worker: Worker, vis: *Vec4f) bool {
        const n = trafo.rotation.r[2];
        const d = n.dot3(trafo.position);
        const hit_t = -(n.dot3(ray.origin) - d) / n.dot3(ray.direction);

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p.sub3(trafo.position);
            const uv = Vec2f.init2(-trafo.rotation.r[0].dot3(k), -trafo.rotation.r[1].dot3(k));

            return worker.scene.propMaterial(entity, 0).visibility(uv, worker, vis);
        }

        return true;
    }
};
