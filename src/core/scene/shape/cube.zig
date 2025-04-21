const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Volume = int.Volume;
const Probe = @import("probe.zig").Probe;
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
    pub fn intersect(ray: Ray, trafo: Trafo) Intersection {
        var hpoint = Intersection{};

        const local_ray = trafo.worldToObjectRay(ray);

        const aabb = AABB.init(@splat(-0.5), @splat(0.5));
        const hit_t = aabb.intersectP(local_ray);
        if (hit_t < ray.max_t) {
            hpoint.t = hit_t;
            hpoint.primitive = 0;
        }

        return hpoint;
    }

    pub fn fragment(ray: Ray, frag: *Fragment) void {
        const hit_t = frag.isec.t;

        frag.p = ray.point(hit_t);

        const local_ray = frag.trafo.worldToObjectRay(ray);
        const local_p = local_ray.point(hit_t);
        const distance = @abs(@as(Vec4f, @splat(0.5)) - @abs(local_p));

        const i = math.indexMinComponent3(distance);
        const s = std.math.copysign(@as(f32, 1.0), local_p[i]);
        const n = @as(Vec4f, @splat(s)) * frag.trafo.rotation.r[i];

        frag.part = 0;
        frag.geo_n = n;
        frag.n = n;
        frag.uvw = @splat(0.0);

        const tb = math.orthonormalBasis3(n);
        frag.t = tb[0];
        frag.b = tb[1];
    }

    pub fn intersectP(ray: Ray, trafo: Trafo) bool {
        const local_ray = trafo.worldToObjectRay(ray);

        const aabb = AABB.init(@splat(-0.5), @splat(0.5));
        return aabb.intersect(local_ray);
    }

    pub fn visibility(ray: Ray, trafo: Trafo, entity: u32, sampler: *Sampler, worker: *const Worker, tr: *Vec4f) bool {
        _ = entity;
        _ = sampler;
        _ = worker;
        _ = tr;

        if (intersectP(ray, trafo)) {
            return false;
        }

        return true;
    }

    pub fn transmittance(
        probe: *const Probe,
        trafo: Trafo,
        entity: u32,
        sampler: *Sampler,
        worker: *Worker,
        tr: *Vec4f,
    ) bool {
        var local_ray = trafo.worldToObjectRay(probe.ray);

        const aabb = AABB.init(@splat(-0.5), @splat(0.5));
        const hit_t = aabb.intersectInterval(local_ray);
        if (std.math.floatMax(f32) == hit_t[0]) {
            return true;
        }

        local_ray.setMinMaxT(hit_t[0], hit_t[1]);

        const material = worker.scene.propMaterial(entity, 0);
        return worker.propTransmittance(local_ray, material, entity, probe.depth.volume, sampler, tr);
    }

    pub fn scatter(
        probe: *const Probe,
        trafo: Trafo,
        throughput: Vec4f,
        entity: u32,
        sampler: *Sampler,
        worker: *Worker,
    ) Volume {
        var local_ray = trafo.worldToObjectRay(probe.ray);

        const aabb = AABB.init(@splat(-0.5), @splat(0.5));
        const hit_t = aabb.intersectInterval(local_ray);
        if (std.math.floatMax(f32) == hit_t[0]) {
            return Volume.initPass(@splat(1.0));
        }

        local_ray.setMinMaxT(hit_t[0], hit_t[1]);

        const material = worker.scene.propMaterial(entity, 0);
        return worker.propScatter(local_ray, throughput, material, entity, probe.depth.volume, sampler);
    }

    pub fn sampleVolumeTo(p: Vec4f, trafo: Trafo, sampler: *Sampler) SampleTo {
        const r3 = sampler.sample3D();
        const xyz = r3 - @as(Vec4f, @splat(0.5));
        const wp = trafo.objectToWorldPoint(xyz);
        const axis = wp - p;

        const sl = math.squaredLength3(axis);
        const t = @sqrt(sl);

        const scale = trafo.scale();
        const volume = scale[0] * scale[1] * scale[2];

        return SampleTo.init(
            wp,
            @splat(0.0),
            axis / @as(Vec4f, @splat(t)),
            r3,
            sl / volume,
        );
    }

    pub fn sampleVolumeToUvw(p: Vec4f, uvw: Vec4f, trafo: Trafo) SampleTo {
        const xyz = uvw - @as(Vec4f, @splat(0.5));
        const wp = trafo.objectToWorldPoint(xyz);
        const axis = wp - p;

        const sl = math.squaredLength3(axis);
        const t = @sqrt(sl);

        const scale = trafo.scale();
        const volume = scale[0] * scale[1] * scale[2];

        return SampleTo.init(
            wp,
            @splat(0.0),
            axis / @as(Vec4f, @splat(t)),
            uvw,
            sl / volume,
        );
    }

    pub fn sampleVolumeFromUvw(uvw: Vec4f, trafo: Trafo, importance_uv: Vec2f) SampleFrom {
        const xyz = uvw - @as(Vec4f, @splat(0.5));
        const wp = trafo.objectToWorldPoint(xyz);

        const dir = math.smpl.sphereUniform(importance_uv);

        const scale = trafo.scale();
        const volume = scale[0] * scale[1] * scale[2];

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

    pub fn volumePdf(p: Vec4f, frag: *const Fragment) f32 {
        const scale = frag.trafo.scale();
        const volume = scale[0] * scale[1] * scale[2];

        const sl = math.squaredDistance3(p, frag.p);
        return sl / volume;
    }
};
