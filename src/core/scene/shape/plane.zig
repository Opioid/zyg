const base = @import("base");
usingnamespace base;

//const Vec4f = base.math.Vec4f;
const Ray = base.math.Ray;

const Transformation = @import("../composed_transformation.zig").Composed_transformation;
const Intersection = @import("../shape/intersection.zig").Intersection;

pub const Plane = struct {
    pub fn intersect(ray: *Ray, trafo: *const Transformation, isec: *Intersection) bool {
        const n = trafo.rotation.r[2];

        const d = n.dot3(trafo.position);
        const hit_t = -(n.dot3(ray.origin) - d) / n.dot3(ray.direction);

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);

            isec.p = p;
            isec.geo_n = n;
            isec.n = n;

            ray.setMaxT(hit_t);
            return true;
        }

        return false;
    }
};
