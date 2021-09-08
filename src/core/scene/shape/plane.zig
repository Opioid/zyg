const base = @import("base");
usingnamespace base;

const Vec2f = base.math.Vec2f;
const Ray = base.math.Ray;

const Transformation = @import("../composed_transformation.zig").Composed_transformation;
const Intersection = @import("intersection.zig").Intersection;

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
};
