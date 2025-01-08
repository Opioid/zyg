const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Scene = @import("../scene.zig").Scene;
const Sampler = @import("../../sampler/sampler.zig").Sampler;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

pub const Plane = struct {
    pub fn intersect(ray: Ray, trafo: Trafo) Intersection {
        var hpoint = Intersection{};

        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t >= ray.min_t and ray.max_t >= hit_t) {
            hpoint.t = hit_t;
            hpoint.primitive = 0;
        }

        return hpoint;
    }

    pub fn fragment(ray: Ray, frag: *Fragment) void {
        const p = ray.point(ray.max_t);
        const k = p - frag.trafo.position;
        const n = frag.trafo.rotation.r[2];
        const t = -frag.trafo.rotation.r[0];
        const b = -frag.trafo.rotation.r[1];

        frag.p = p;
        frag.geo_n = n;
        frag.t = t;
        frag.b = b;
        frag.n = n;
        frag.uvw = .{ math.dot3(t, k), math.dot3(b, k), 0.0, 0.0 };
        frag.part = 0;
    }

    pub fn intersectP(ray: Ray, trafo: Trafo) bool {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t >= ray.min_t and ray.max_t >= hit_t) {
            return true;
        }

        return false;
    }

    pub fn visibility(ray: Ray, trafo: Trafo, entity: u32, sampler: *Sampler, scene: *const Scene, tr: *Vec4f) bool {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t >= ray.min_t and ray.max_t >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const uv = Vec2f{ -math.dot3(trafo.rotation.r[0], k), -math.dot3(trafo.rotation.r[1], k) };

            return scene.propMaterial(entity, 0).visibility(ray.direction, n, uv, sampler, scene, tr);
        }

        return true;
    }
};
