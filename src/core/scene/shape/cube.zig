const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Interpolation = int.Interpolation;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const Scene = @import("../scene.zig").Scene;
const Filter = @import("../../image/texture/texture_sampler.zig").Filter;
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
        const local_origin = trafo.worldToObjectPoint(ray.origin);
        const local_dir = trafo.worldToObjectVector(ray.direction);

        const local_ray = Ray.init(local_origin, local_dir, ray.minT(), ray.maxT());

        const aabb = AABB.init(@splat(4, @as(f32, -1.0)), @splat(4, @as(f32, 1.0)));
        const hit_t = aabb.intersectP(local_ray) orelse return false;
        if (hit_t > ray.maxT()) {
            return false;
        }

        ray.setMaxT(hit_t);

        isec.p = ray.point(hit_t);

        const local_p = local_ray.point(hit_t);
        const distance = @fabs(@splat(4, @as(f32, 1.0)) - @fabs(local_p));

        const i = math.indexMinComponent3(distance);
        const s = std.math.copysign(@as(f32, 1.0), local_p[i]);
        const n = @splat(4, s) * trafo.rotation.r[i];

        isec.part = 0;
        isec.primitive = 0;
        isec.geo_n = n;
        isec.n = n;

        if (.Normal != ipo) {
            const tb = math.orthonormalBasis3(n);
            isec.t = tb[0];
            isec.b = tb[1];
        }

        return true;
    }

    pub fn intersectP(ray: Ray, trafo: Trafo) bool {
        const local_origin = trafo.worldToObjectPoint(ray.origin);
        const local_dir = trafo.worldToObjectVector(ray.direction);

        const local_ray = Ray.init(local_origin, local_dir, ray.minT(), ray.maxT());

        const aabb = AABB.init(@splat(4, @as(f32, -1.0)), @splat(4, @as(f32, 1.0)));

        return aabb.intersect(local_ray);
    }

    pub fn visibility(ray: Ray, trafo: Trafo, entity: usize, filter: ?Filter, scene: *const Scene) ?Vec4f {
        _ = ray;
        _ = trafo;
        _ = entity;
        _ = filter;
        _ = scene;

        return @splat(4, @as(f32, 1.0));
    }

    pub fn sampleVolumeTo(p: Vec4f, trafo: Trafo, sampler: *Sampler) SampleTo {
        const r3 = sampler.sample3D();
        const xyz = @splat(4, @as(f32, 2.0)) * (r3 - @splat(4, @as(f32, 0.5)));
        const wp = trafo.objectToWorldPoint(xyz);
        const axis = wp - p;

        const sl = math.squaredLength3(axis);
        const t = @sqrt(sl);

        const d = @splat(4, @as(f32, 2.0)) * trafo.scale();
        const volume = d[0] * d[1] * d[2];

        return SampleTo.init(
            axis / @splat(4, t),
            @splat(4, @as(f32, 0.0)),
            r3,
            trafo,
            sl / volume,
            t,
        );
    }

    pub fn sampleVolumeToUvw(p: Vec4f, uvw: Vec4f, trafo: Trafo) SampleTo {
        const xyz = @splat(4, @as(f32, 2.0)) * (uvw - @splat(4, @as(f32, 0.5)));
        const wp = trafo.objectToWorldPoint(xyz);
        const axis = wp - p;

        const sl = math.squaredLength3(axis);
        const t = @sqrt(sl);

        const d = @splat(4, @as(f32, 2.0)) * trafo.scale();
        const volume = d[0] * d[1] * d[2];

        return SampleTo.init(
            axis / @splat(4, t),
            @splat(4, @as(f32, 0.0)),
            uvw,
            trafo,
            sl / volume,
            t,
        );
    }

    pub fn sampleVolumeFromUvw(uvw: Vec4f, trafo: Trafo, importance_uv: Vec2f) SampleFrom {
        const xyz = @splat(4, @as(f32, 2.0)) * (uvw - @splat(4, @as(f32, 0.5)));
        const wp = trafo.objectToWorldPoint(xyz);

        const dir = math.smpl.sphereUniform(importance_uv);

        const d = @splat(4, @as(f32, 2.0)) * trafo.scale();
        const volume = d[0] * d[1] * d[2];

        return SampleFrom.init(
            wp,
            dir,
            @splat(4, @as(f32, 0.0)),
            uvw,
            importance_uv,
            trafo,
            1.0 / (4.0 * std.math.pi * volume),
        );
    }

    pub fn volumePdf(ray: Ray, scale: Vec4f) f32 {
        const d = @splat(4, @as(f32, 2.0)) * scale;
        const volume = d[0] * d[1] * d[2];

        const t = ray.maxT();
        return (t * t) / volume;
    }
};
