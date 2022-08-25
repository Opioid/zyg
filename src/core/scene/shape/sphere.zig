const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const Scene = @import("../scene.zig").Scene;
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

pub const Sphere = struct {
    fn intersectDetail(hit_t: f32, ray: Ray, trafo: Trafo, isec: *Intersection) void {
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
        isec.uv = Vec2f{ phi * (0.5 * math.pi_inv), theta * math.pi_inv };
    }

    pub fn intersect(ray: *Ray, trafo: Trafo, isec: *Intersection) bool {
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

    pub fn intersectP(ray: Ray, trafo: Trafo) bool {
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

    pub fn visibility(ray: Ray, trafo: Trafo, entity: usize, filter: ?Filter, scene: Scene) ?Vec4f {
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
                const uv = Vec2f{ phi * (0.5 * math.pi_inv), theta * math.pi_inv };

                return scene.propMaterial(entity, 0).visibility(ray.direction, n, uv, filter, scene);
            }

            const t1 = b + dist;
            if (t1 > ray.minT() and t1 < ray.maxT()) {
                const p = ray.point(t1);
                const n = math.normalize3(p - trafo.position);
                const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(n));
                const phi = -std.math.atan2(f32, xyz[0], xyz[2]) + std.math.pi;
                const theta = std.math.acos(xyz[1]);
                const uv = Vec2f{ phi * (0.5 * math.pi_inv), theta * math.pi_inv };

                return scene.propMaterial(entity, 0).visibility(ray.direction, n, uv, filter, scene);
            }
        }

        return @splat(4, @as(f32, 1.0));
    }

    pub fn sampleTo(p: Vec4f, trafo: Trafo, sampler: *Sampler, rng: *RNG) ?SampleTo {
        const v = trafo.position - p;
        const il = math.rlength3(v);
        const radius = trafo.scaleX();
        const sin_theta_max = std.math.min(il * radius, 1.0);
        const cos_theta_max = @sqrt(std.math.max(1.0 - sin_theta_max * sin_theta_max, math.smpl.Eps));

        const z = @splat(4, il) * v;
        const xy = math.orthonormalBasis3(z);

        const r2 = sampler.sample2D(rng);
        const dir = math.smpl.orientedConeUniform(r2, cos_theta_max, xy[0], xy[1], z);

        const b = math.dot3(dir, v);
        const remedy_term = v - @splat(4, b) * dir;
        const discriminant = radius * radius - math.dot3(remedy_term, remedy_term);

        if (discriminant > 0.0) {
            const dist = @sqrt(discriminant);
            const t = b - dist;

            return SampleTo.init(
                dir,
                trafo.rotation.r[2],
                @splat(4, @as(f32, 0.0)),
                trafo,
                math.smpl.conePdfUniform(cos_theta_max),
                ro.offsetB(t),
            );
        }

        return null;
    }

    pub fn sampleToUv(p: Vec4f, uv: Vec2f, trafo: Trafo, area: f32) ?SampleTo {
        const phi = (uv[0] + 0.75) * (2.0 * std.math.pi);
        const theta = uv[1] * std.math.pi;

        // avoid singularity at poles
        const sin_theta = std.math.max(@sin(theta), 0.00001);
        const cos_theta = @cos(theta);
        const sin_phi = @sin(phi);
        const cos_phi = @cos(phi);

        const ls = Vec4f{ sin_theta * cos_phi, cos_theta, sin_theta * sin_phi, 0.0 };
        const ws = trafo.objectToWorldPoint(ls);

        const axis = ws - p;
        const sl = math.squaredLength3(axis);
        const t = @sqrt(sl);
        const dir = axis / @splat(4, @as(f32, t));
        const wn = math.normalize3(ws - trafo.position);
        const c = -math.dot3(wn, dir);

        if (c < Dot_min) {
            return null;
        }

        return SampleTo.init(
            dir,
            wn,
            .{ uv[0], uv[1], 0.0, 0.0 },
            trafo,
            sl / (c * area * sin_theta),
            ro.offsetB(t),
        );
    }

    pub fn sampleFrom(trafo: Trafo, area: f32, uv: Vec2f, importance_uv: Vec2f) ?SampleFrom {
        const ls = math.smpl.sphereUniform(uv);
        const ws = trafo.objectToWorldPoint(ls);

        const wn = math.normalize3(ws - trafo.position);
        const xy = math.orthonormalBasis3(ls);
        const dir = math.smpl.orientedHemisphereCosine(importance_uv, xy[0], xy[1], ls);

        return SampleFrom.init(
            ro.offsetRay(ws, wn),
            wn,
            dir,
            .{ uv[0], uv[1], 0.0, 0.0 },
            importance_uv,
            trafo,
            1.0 / (std.math.pi * area),
        );
    }

    pub fn pdf(ray: Ray, trafo: Trafo) f32 {
        const axis = trafo.position - ray.origin;

        const il = math.rlength3(axis);
        const radius = trafo.scaleX();
        const sin_theta_max = std.math.min(il * radius, 1.0);
        const cos_theta_max = @sqrt(std.math.max(1.0 - sin_theta_max * sin_theta_max, math.smpl.Eps));

        return math.smpl.conePdfUniform(cos_theta_max);
    }

    pub fn pdfUv(ray: Ray, isec: Intersection, area: f32) f32 {
        // avoid singularity at poles
        const sin_theta = std.math.max(@sin(isec.uv[1] * std.math.pi), 0.00001);

        const max_t = ray.maxT();
        const sl = max_t * max_t;
        const c = -math.dot3(isec.geo_n, ray.direction);
        return sl / (c * area * sin_theta);
    }
};
