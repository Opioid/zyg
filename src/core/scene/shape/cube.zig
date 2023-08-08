const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Interpolation = int.Interpolation;
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
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const Cube = struct {
    pub fn intersect(ray: *Ray, trafo: Trafo, ipo: Interpolation, isec: *Intersection) bool {
        const local_ray = trafo.worldToObjectRay(ray.*);

        const aabb = AABB.init(@splat(-1.0), @splat(1.0));
        const hit_t = aabb.intersectP(local_ray) orelse return false;
        if (hit_t > ray.maxT()) {
            return false;
        }

        ray.setMaxT(hit_t);

        isec.p = ray.point(hit_t);

        const local_p = local_ray.point(hit_t);
        const distance = @fabs(@as(Vec4f, @splat(1.0)) - @fabs(local_p));

        const i = math.indexMinComponent3(distance);
        const s = std.math.copysign(@as(f32, 1.0), local_p[i]);
        const n = @as(Vec4f, @splat(s)) * trafo.rotation.r[i];

        isec.offset = 0.0;
        isec.part = 0;
        isec.primitive = 0;
        isec.geo_n = n;
        isec.n = n;

        if (.All == ipo) {
            const tb = math.orthonormalBasis3(n);
            isec.t = tb[0];
            isec.b = tb[1];
        }

        return true;
    }

    pub fn intersectP(ray: Ray, trafo: Trafo) bool {
        const local_ray = trafo.worldToObjectRay(ray);

        const aabb = AABB.init(@splat(-1.0), @splat(1.0));
        return aabb.intersect(local_ray);
    }

    pub fn visibility(ray: Ray, trafo: Trafo, entity: u32, sampler: *Sampler, scene: *const Scene) ?Vec4f {
        _ = entity;
        _ = sampler;
        _ = scene;

        return if (intersectP(ray, trafo)) null else @splat(1.0);
    }

    pub fn transmittance(
        ray: Ray,
        trafo: Trafo,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        worker: *Worker,
    ) ?Vec4f {
        var local_ray = trafo.worldToObjectRay(ray);

        const aabb = AABB.init(@splat(-1.0), @splat(1.0));
        const hit_t = aabb.intersectP2(local_ray) orelse return @splat(1.0);

        const start = math.max(hit_t[0], ray.minT());
        const end = math.min(hit_t[1], ray.maxT());
        local_ray.setMinMaxT(start, end);

        const material = worker.scene.propMaterial(entity, 0);
        return worker.propTransmittance(local_ray, material, entity, depth, sampler);
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
        const local_origin = trafo.worldToObjectPoint(ray.origin);
        const local_dir = trafo.worldToObjectVector(ray.direction);
        const local_ray = Ray.init(local_origin, local_dir, ray.minT(), ray.maxT());

        const aabb = AABB.init(@splat(-1.0), @splat(1.0));
        const hit_t = aabb.intersectP2(local_ray) orelse return Volume.initPass(@splat(1.0));

        const start = math.max(hit_t[0], ray.minT());
        const end = math.min(hit_t[1], ray.maxT());

        const material = worker.scene.propMaterial(entity, 0);
        const tray = Ray.init(local_origin, local_dir, start, end);
        return worker.propScatter(tray, throughput, material, entity, depth, sampler);
    }

    pub fn sampleVolumeTo(p: Vec4f, trafo: Trafo, sampler: *Sampler) SampleTo {
        const r3 = sampler.sample3D();
        const xyz = @as(Vec4f, @splat(2.0)) * (r3 - @as(Vec4f, @splat(0.5)));
        const wp = trafo.objectToWorldPoint(xyz);
        const axis = wp - p;

        const sl = math.squaredLength3(axis);
        const t = @sqrt(sl);

        const d = @as(Vec4f, @splat(2.0)) * trafo.scale();
        const volume = d[0] * d[1] * d[2];

        return SampleTo.init(
            wp,
            @splat(0.0),
            axis / @as(Vec4f, @splat(t)),
            r3,
            trafo,
            sl / volume,
        );
    }

    pub fn sampleVolumeToUvw(p: Vec4f, uvw: Vec4f, trafo: Trafo) SampleTo {
        const xyz = @as(Vec4f, @splat(2.0)) * (uvw - @as(Vec4f, @splat(0.5)));
        const wp = trafo.objectToWorldPoint(xyz);
        const axis = wp - p;

        const sl = math.squaredLength3(axis);
        const t = @sqrt(sl);

        const d = @as(Vec4f, @splat(2.0)) * trafo.scale();
        const volume = d[0] * d[1] * d[2];

        return SampleTo.init(
            wp,
            @splat(0.0),
            axis / @as(Vec4f, @splat(t)),
            uvw,
            trafo,
            sl / volume,
        );
    }

    pub fn sampleVolumeFromUvw(uvw: Vec4f, trafo: Trafo, importance_uv: Vec2f) SampleFrom {
        const xyz = @as(Vec4f, @splat(2.0)) * (uvw - @as(Vec4f, @splat(0.5)));
        const wp = trafo.objectToWorldPoint(xyz);

        const dir = math.smpl.sphereUniform(importance_uv);

        const d = @as(Vec4f, @splat(2.0)) * trafo.scale();
        const volume = d[0] * d[1] * d[2];

        return SampleFrom.init(
            wp,
            dir,
            @splat(0.0),
            uvw,
            importance_uv,
            trafo,
            1.0 / (4.0 * std.math.pi * volume),
        );
    }

    pub fn volumePdf(ray: Ray, scale: Vec4f) f32 {
        const d = @as(Vec4f, @splat(2.0)) * scale;
        const volume = d[0] * d[1] * d[2];

        const t = ray.maxT();
        return (t * t) / volume;
    }
};
