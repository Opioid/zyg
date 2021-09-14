const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const Worker = @import("../worker.zig").Worker;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const Sphere = struct {
    fn intersectDetail(hit_t: f32, ray: Ray, trafo: Transformation, isec: *Intersection) void {
        const p = ray.point(hit_t);
        const n = math.normalize3(p - trafo.position);

        isec.p = p;
        isec.geo_n = n;
        isec.n = n;
        isec.part = 0;

        const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(n));
        const phi = -std.math.atan2(f32, xyz[0], xyz[2]) + std.math.pi;
        const theta = std.math.acos(xyz[1]);

        const sin_phi = @sin(phi);
        const cos_phi = @cos(phi);
        // avoid singularity at poles
        const sin_theta = std.math.max(@sin(theta), 0.00001);

        const t = math.normalize3(trafo.rotation.transformVector(.{
            sin_theta * cos_phi,
            0.0,
            sin_theta * sin_phi,
            0.0,
        }));

        isec.t = t;
        isec.b = -math.cross3(t, n);
        isec.uv = Vec2f.init2(phi * (0.5 * math.pi_inv), theta * math.pi_inv);
    }

    pub fn intersect(ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        const v = trafo.position - ray.origin;
        const b = math.dot3(ray.direction, v);

        const remedy_term = v - @splat(4, b) * ray.direction;
        const radius = trafo.scaleX();
        const discriminant = radius * radius - math.dot3(remedy_term, remedy_term);

        if (discriminant > 0.0) {
            const dist = @sqrt(discriminant);

            const t0 = b - dist;
            if (t0 > ray.minT() and t0 < ray.maxT()) {
                intersectDetail(t0, ray.*, trafo, isec);

                ray.setMaxT(t0);
                return true;
            }

            const t1 = b + dist;
            if (t1 > ray.minT() and t1 < ray.maxT()) {
                intersectDetail(t1, ray.*, trafo, isec);

                ray.setMaxT(t1);
                return true;
            }
        }

        return false;
    }

    pub fn intersectP(ray: Ray, trafo: Transformation) bool {
        const v = trafo.position - ray.origin;
        const b = math.dot3(ray.direction, v);

        const remedy_term = v - @splat(4, b) * ray.direction;
        const radius = trafo.scaleX();
        const discriminant = radius * radius - math.dot3(remedy_term, remedy_term);

        if (discriminant > 0.0) {
            const dist = @sqrt(discriminant);
            const t0 = b - dist;

            if (t0 > ray.minT() and t0 < ray.maxT()) {
                return true;
            }

            const t1 = b + dist;

            if (t1 > ray.minT() and t1 < ray.maxT()) {
                return true;
            }
        }

        return false;
    }

    pub fn visibility(ray: Ray, trafo: Transformation, entity: usize, worker: Worker, vis: *Vec4f) bool {
        const v = trafo.position - ray.origin;
        const b = math.dot3(ray.direction, v);

        const remedy_term = v - @splat(4, b) * ray.direction;
        const radius = trafo.scaleX();
        const discriminant = radius * radius - math.dot3(remedy_term, remedy_term);

        if (discriminant > 0.0) {
            const dist = @sqrt(discriminant);

            const t0 = b - dist;
            if (t0 > ray.minT() and t0 < ray.maxT()) {
                const p = ray.point(t0);
                const n = math.normalize3(p - trafo.position);
                const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(n));
                const phi = -std.math.atan2(f32, xyz[0], xyz[2]) + std.math.pi;
                const theta = std.math.acos(xyz[1]);
                const uv = Vec2f.init2(phi * (0.5 * math.pi_inv), theta * math.pi_inv);

                return worker.scene.propMaterial(entity, 0).visibility(uv, worker, vis);
            }

            const t1 = b + dist;
            if (t1 > ray.minT() and t1 < ray.maxT()) {
                const p = ray.point(t1);
                const n = math.normalize3(p - trafo.position);
                const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(n));
                const phi = -std.math.atan2(f32, xyz[0], xyz[2]) + std.math.pi;
                const theta = std.math.acos(xyz[1]);
                const uv = Vec2f.init2(phi * (0.5 * math.pi_inv), theta * math.pi_inv);

                return worker.scene.propMaterial(entity, 0).visibility(uv, worker, vis);
            }
        }

        return false;
    }
};
