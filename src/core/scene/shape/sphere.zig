const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Volume = int.Volume;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const Scene = @import("../scene.zig").Scene;
const Worker = @import("../../rendering/worker.zig").Worker;
const ro = @import("../ray_offset.zig");

const base = @import("base");
const math = base.math;
const Frame = math.Frame;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const Sphere = struct {
    pub fn intersect(ray: Ray, trafo: Trafo) Intersection {
        const v = trafo.position - ray.origin;
        const b = math.dot3(ray.direction, v);

        const remedy_term = v - @as(Vec4f, @splat(b)) * ray.direction;
        const radius = trafo.scaleX();
        const discriminant = radius * radius - math.dot3(remedy_term, remedy_term);

        var hpoint = Intersection{};

        if (discriminant > 0.0) {
            const dist = @sqrt(discriminant);

            const t0 = b - dist;
            if (t0 >= ray.minT() and ray.maxT() >= t0) {
                hpoint.t = t0;
                hpoint.primitive = 0;
                return hpoint;
            }

            const t1 = b + dist;
            if (t1 >= ray.minT() and ray.maxT() >= t1) {
                hpoint.t = t1;
                hpoint.primitive = 0;
                return hpoint;
            }
        }

        return hpoint;
    }

    pub fn fragment(ray: Ray, frag: *Fragment) void {
        const p = ray.point(ray.maxT());
        const n = math.normalize3(p - frag.trafo.position);

        frag.p = p;
        frag.geo_n = n;
        frag.n = n;
        frag.part = 0;

        const xyz = math.normalize3(frag.trafo.rotation.transformVectorTransposed(n));
        const phi = -std.math.atan2(xyz[0], xyz[2]) + std.math.pi;
        const theta = std.math.acos(xyz[1]);

        const sin_phi = @sin(phi);
        const cos_phi = @cos(phi);
        // avoid singularity at poles
        const sin_theta = math.max(@sin(theta), 0.00001);

        const t = math.normalize3(frag.trafo.rotation.transformVector(.{
            sin_theta * cos_phi,
            0.0,
            sin_theta * sin_phi,
            0.0,
        }));

        frag.t = t;
        frag.b = -math.cross3(t, n);
        frag.uvw = .{ phi * (0.5 * math.pi_inv), theta * math.pi_inv, 0.0, 0.0 };
    }

    pub fn intersectP(ray: Ray, trafo: Trafo) bool {
        const v = trafo.position - ray.origin;
        const b = math.dot3(ray.direction, v);

        const remedy_term = v - @as(Vec4f, @splat(b)) * ray.direction;
        const radius = trafo.scaleX();
        const discriminant = radius * radius - math.dot3(remedy_term, remedy_term);

        if (discriminant > 0.0) {
            const dist = @sqrt(discriminant);
            const t0 = b - dist;

            if (t0 >= ray.minT() and ray.maxT() >= t0) {
                return true;
            }

            const t1 = b + dist;

            if (t1 >= ray.minT() and ray.maxT() >= t1) {
                return true;
            }
        }

        return false;
    }

    pub fn visibility(ray: Ray, trafo: Trafo, entity: u32, sampler: *Sampler, scene: *const Scene, tr: *Vec4f) bool {
        const v = trafo.position - ray.origin;
        const b = math.dot3(ray.direction, v);

        const remedy_term = v - @as(Vec4f, @splat(b)) * ray.direction;
        const radius = trafo.scaleX();
        const discriminant = radius * radius - math.dot3(remedy_term, remedy_term);

        if (discriminant > 0.0) {
            const dist = @sqrt(discriminant);

            const t0 = b - dist;
            if (t0 >= ray.minT() and ray.maxT() >= t0) {
                const p = ray.point(t0);
                const n = math.normalize3(p - trafo.position);
                const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(n));
                const phi = -std.math.atan2(xyz[0], xyz[2]) + std.math.pi;
                const theta = std.math.acos(xyz[1]);
                const uv = Vec2f{ phi * (0.5 * math.pi_inv), theta * math.pi_inv };

                if (!scene.propMaterial(entity, 0).visibility(ray.direction, n, uv, sampler, scene, tr)) {
                    return false;
                }
            }

            const t1 = b + dist;
            if (t1 >= ray.minT() and ray.maxT() >= t1) {
                const p = ray.point(t1);
                const n = math.normalize3(p - trafo.position);
                const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(n));
                const phi = -std.math.atan2(xyz[0], xyz[2]) + std.math.pi;
                const theta = std.math.acos(xyz[1]);
                const uv = Vec2f{ phi * (0.5 * math.pi_inv), theta * math.pi_inv };

                if (!scene.propMaterial(entity, 0).visibility(ray.direction, n, uv, sampler, scene, tr)) {
                    return false;
                }
            }
        }

        return true;
    }

    pub fn transmittance(
        ray: Ray,
        trafo: Trafo,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        worker: *Worker,
        tr: *Vec4f,
    ) bool {
        const v = trafo.position - ray.origin;
        const b = math.dot3(ray.direction, v);

        const remedy_term = v - @as(Vec4f, @splat(b)) * ray.direction;
        const radius = trafo.scaleX();
        const discriminant = radius * radius - math.dot3(remedy_term, remedy_term);

        if (discriminant > 0.0) {
            const dist = @sqrt(discriminant);
            const t0 = b - dist;
            const t1 = b + dist;
            const start = math.max(t0, ray.minT());
            const end = math.min(t1, ray.maxT());

            const material = worker.scene.propMaterial(entity, 0);

            const tray = Ray.init(
                trafo.worldToObjectPoint(ray.origin),
                trafo.worldToObjectVector(ray.direction),
                start,
                end,
            );
            return worker.propTransmittance(tray, material, entity, depth, sampler, tr);
        }

        return true;
    }

    pub fn scatter(
        ray: Ray,
        trafo: Trafo,
        throughput: Vec4f,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        worker: *Worker,
    ) Volume {
        const v = trafo.position - ray.origin;
        const b = math.dot3(ray.direction, v);

        const remedy_term = v - @as(Vec4f, @splat(b)) * ray.direction;
        const radius = trafo.scaleX();
        const discriminant = radius * radius - math.dot3(remedy_term, remedy_term);

        if (discriminant > 0.0) {
            const dist = @sqrt(discriminant);
            const t0 = b - dist;
            const t1 = b + dist;
            const start = math.max(t0, ray.minT());
            const end = math.min(t1, ray.maxT());

            const material = worker.scene.propMaterial(entity, 0);

            const tray = Ray.init(
                trafo.worldToObjectPoint(ray.origin),
                trafo.worldToObjectVector(ray.direction),
                start,
                end,
            );

            return worker.propScatter(tray, throughput, material, entity, depth, sampler);
        }

        return Volume.initPass(@splat(1.0));
    }

    pub fn sampleTo(p: Vec4f, trafo: Trafo, sampler: *Sampler) ?SampleTo {
        const v = trafo.position - p;
        const l = math.length3(v);
        const r = trafo.scaleX();

        if (l <= (r + 0.0000001)) {
            return null;
        }

        const sin_theta_max = r / l;
        const sin2_theta_max = sin_theta_max * sin_theta_max;
        const cos_theta_max = @sqrt(1.0 - sin2_theta_max);
        var one_minus_cos_theta_max = 1.0 - cos_theta_max;

        const s2 = sampler.sample2D();

        var cos_theta = (cos_theta_max - 1.0) * s2[0] + 1.0;
        var sin2_theta = 1.0 - (cos_theta * cos_theta);

        if (sin2_theta_max < 0.00068523) {
            sin2_theta = sin2_theta_max * s2[0];
            cos_theta = @sqrt(1.0 - sin2_theta);
            one_minus_cos_theta_max = 0.5 * sin2_theta_max;
        }

        const cos_alpha = sin2_theta / sin_theta_max + cos_theta * @sqrt(1.0 - math.min(sin2_theta / sin2_theta_max, 1.0));
        const sin_alpha = @sqrt(1.0 - cos_alpha * cos_alpha);

        const phi = s2[1] * (2.0 * std.math.pi);

        const z = @as(Vec4f, @splat(1.0 / l)) * v;
        const frame = Frame.init(z);

        const w = math.smpl.sphereDirection(sin_alpha, cos_alpha, phi);
        const n = frame.frameToWorld(-w);

        const lp = trafo.position + @as(Vec4f, @splat(r)) * n;

        const dir = math.normalize3(lp - p);

        return SampleTo.init(
            lp,
            n,
            dir,
            @splat(0.0),
            math.smpl.conePdfUniform(one_minus_cos_theta_max),
        );
    }

    pub fn sampleToUv(p: Vec4f, uv: Vec2f, trafo: Trafo) ?SampleTo {
        const phi = (uv[0] + 0.75) * (2.0 * std.math.pi);
        const theta = uv[1] * std.math.pi;

        // avoid singularity at poles
        const sin_theta = math.max(@sin(theta), 0.00001);
        const cos_theta = @cos(theta);
        const sin_phi = @sin(phi);
        const cos_phi = @cos(phi);

        const ls = Vec4f{ sin_theta * cos_phi, cos_theta, sin_theta * sin_phi, 0.0 };
        const ws = trafo.objectToWorldPoint(ls);

        const axis = ws - p;
        const sl = math.squaredLength3(axis);
        const t = @sqrt(sl);
        const dir = axis / @as(Vec4f, @splat(t));
        const wn = math.normalize3(ws - trafo.position);
        const c = -math.dot3(wn, dir);

        if (c < math.safe.Dot_min) {
            return null;
        }

        const r = trafo.scaleX();
        const area = (4.0 * std.math.pi) * (r * r);

        return SampleTo.init(
            ws,
            wn,
            dir,
            .{ uv[0], uv[1], 0.0, 0.0 },
            sl / (c * area * sin_theta),
        );
    }

    pub fn sampleFrom(trafo: Trafo, uv: Vec2f, importance_uv: Vec2f) ?SampleFrom {
        const ls = math.smpl.sphereUniform(uv);
        const ws = trafo.objectToWorldPoint(ls);
        const wn = math.normalize3(ws - trafo.position);

        const dir_l = math.smpl.hemisphereCosine(importance_uv);
        const frame = Frame.init(wn);
        const dir = frame.frameToWorld(dir_l);

        const r = trafo.scaleX();
        const area = (4.0 * std.math.pi) * (r * r);

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

    pub fn pdf(p: Vec4f, trafo: Trafo) f32 {
        const v = trafo.position - p;
        const l2 = math.squaredLength3(v);
        const r = trafo.scaleX();
        const r2 = r * r;
        const sin2_theta_max = r2 / l2;

        const one_minus_cos_theta_max = if (sin2_theta_max < 0.00068523)
            0.5 * sin2_theta_max
        else
            1.0 - @sqrt(math.max(1.0 - sin2_theta_max, 0.0));

        return math.smpl.conePdfUniform(one_minus_cos_theta_max);
    }

    pub fn pdfUv(dir: Vec4f, p: Vec4f, frag: *const Fragment) f32 {
        // avoid singularity at poles
        const sin_theta = math.max(@sin(frag.uvw[1] * std.math.pi), 0.00001);

        const sl = math.squaredDistance3(p, frag.p);
        const c = -math.dot3(frag.geo_n, dir);

        const r = frag.trafo.scaleX();
        const area = (4.0 * std.math.pi) * (r * r);

        return sl / (c * area * sin_theta);
    }
};
