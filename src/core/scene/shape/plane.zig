const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const Scene = @import("../scene.zig").Scene;
const Filter = @import("../../image/texture/texture_sampler.zig").Filter;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

pub const Plane = struct {
    pub fn intersect(ray: *Ray, trafo: Trafo, isec: *Intersection) bool {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t >= ray.minT() and ray.maxT() >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];
            const b = -trafo.rotation.r[1];

            isec.p = p;
            isec.geo_n = n;
            isec.t = t;
            isec.b = b;
            isec.n = n;
            isec.uv = Vec2f{ math.dot3(t, k), math.dot3(b, k) };
            isec.part = 0;

            ray.setMaxT(hit_t);
            return true;
        }

        return false;
    }

    pub fn intersectP(ray: Ray, trafo: Trafo) bool {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t >= ray.minT() and ray.maxT() >= hit_t) {
            return true;
        }

        return false;
    }

    pub fn visibility(ray: Ray, trafo: Trafo, entity: usize, filter: ?Filter, scene: *const Scene) ?Vec4f {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t >= ray.minT() and ray.maxT() >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const uv = Vec2f{ -math.dot3(trafo.rotation.r[0], k), -math.dot3(trafo.rotation.r[1], k) };

            return scene.propMaterial(entity, 0).visibility(ray.direction, n, uv, filter, scene);
        }

        return @splat(4, @as(f32, 1.0));
    }
};
