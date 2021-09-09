const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const Sphere = struct {
    fn intersectDetail(hit_t: f32, ray: Ray, trafo: Transformation, isec: *Intersection) void {
        const p = ray.point(hit_t);
        const n = p.sub3(trafo.position).normalize3();

        isec.p = p;
        isec.geo_n = n;
        isec.n = n;
        isec.part = 0;

        const xyz = trafo.rotation.transformVectorTransposed(n).normalize3();

        const phi = -std.math.atan2(f32, xyz.v[0], xyz.v[2]) + std.math.pi;
        const theta = std.math.acos(xyz.v[1]);

        const sin_phi = @sin(phi);
        const cos_phi = @cos(phi);
        // avoid singularity at poles
        const sin_theta = std.math.max(@sin(theta), 0.00001);

        const t = trafo.rotation.transformVector(Vec4f.init3(
            sin_theta * cos_phi,
            0.0,
            sin_theta * sin_phi,
        )).normalize3();

        isec.t = t;
        isec.b = t.cross3(n).neg3();
        isec.uv = Vec2f.init2(phi * (0.5 * math.pi_inv), theta * math.pi_inv);
    }

    pub fn intersect(ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        const v = trafo.position.sub3(ray.origin);

        const b = ray.direction.dot3(v);

        const remedy_term = v.sub3(ray.direction.mulScalar3(b));

        const radius = trafo.scaleX();

        const discriminant = radius * radius - remedy_term.dot3(remedy_term);

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
        const v = trafo.position.sub3(ray.origin);

        const b = ray.direction.dot3(v);

        const remedy_term = v.sub3(ray.direction.mulScalar3(b));

        const radius = trafo.scaleX();

        const discriminant = radius * radius - remedy_term.dot3(remedy_term);

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
};
