const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const Rectangle = struct {
    pub fn intersect(ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        const normal = trafo.rotation.r[2];
        const d = normal.dot3(trafo.position);
        const denom = -normal.dot3(ray.direction);
        const numer = normal.dot3(ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p.sub3(trafo.position);
            const t = trafo.rotation.r[0].neg3();

            const u = t.dot3(k.divScalar3(trafo.scaleX()));
            if (u > 1.0 or u < -1.0) {
                return false;
            }

            const b = trafo.rotation.r[1].neg3();

            const v = b.dot3(k.divScalar3(trafo.scaleY()));
            if (v > 1.0 or v < -1.0) {
                return false;
            }

            isec.p = p;
            isec.t = t;
            isec.b = b;
            isec.n = normal;
            isec.geo_n = normal;
            isec.uv.v[0] = 0.5 * (u + 1.0);
            isec.uv.v[1] = 0.5 * (v + 1.0);
            isec.part = 0;

            ray.setMaxT(hit_t);
            return true;
        }

        return false;
    }

    pub fn intersectP(ray: Ray, trafo: Transformation) bool {
        const normal = trafo.rotation.r[2];
        const d = normal.dot3(trafo.position);
        const denom = -normal.dot3(ray.direction);
        const numer = normal.dot3(ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p.sub3(trafo.position);
            const t = trafo.rotation.r[0].neg3();

            const u = t.dot3(k.divScalar3(trafo.scaleX()));
            if (u > 1.0 or u < -1.0) {
                return false;
            }

            const b = trafo.rotation.r[1].neg3();

            const v = b.dot3(k.divScalar3(trafo.scaleY()));
            if (v > 1.0 or v < -1.0) {
                return false;
            }

            return true;
        }

        return false;
    }
};
