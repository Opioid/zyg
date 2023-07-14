const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const Scene = @import("../scene.zig").Scene;
const ro = @import("../ray_offset.zig");
const Dot_min = @import("../material/sample_helper.zig").Dot_min;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const Rectangle = struct {
    pub fn intersect(ray: *Ray, trafo: Trafo, isec: *Intersection) bool {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t >= ray.minT() and ray.maxT() >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];

            const u = math.dot3(t, k / @as(Vec4f, @splat(trafo.scaleX())));
            if (u > 1.0 or u < -1.0) {
                return false;
            }

            const b = -trafo.rotation.r[1];

            const v = math.dot3(b, k / @as(Vec4f, @splat(trafo.scaleY())));
            if (v > 1.0 or v < -1.0) {
                return false;
            }

            isec.p = p;
            isec.t = t;
            isec.b = b;
            isec.n = normal;
            isec.geo_n = normal;
            isec.uv = .{ 0.5 * (u + 1.0), 0.5 * (v + 1.0) };
            isec.part = 0;

            ray.setMaxT(hit_t);
            return true;
        }

        return false;
    }

    pub fn intersectP(ray: Ray, trafo: Trafo) bool {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t >= ray.minT() and ray.maxT() >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];

            const u = math.dot3(t, k / @as(Vec4f, @splat(trafo.scaleX())));
            if (u > 1.0 or u < -1.0) {
                return false;
            }

            const b = -trafo.rotation.r[1];

            const v = math.dot3(b, k / @as(Vec4f, @splat(trafo.scaleY())));
            if (v > 1.0 or v < -1.0) {
                return false;
            }

            return true;
        }

        return false;
    }

    pub fn visibility(ray: Ray, trafo: Trafo, entity: u32, sampler: *Sampler, scene: *const Scene) ?Vec4f {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t >= ray.minT() and ray.maxT() >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];

            const u = math.dot3(t, k / @as(Vec4f, @splat(trafo.scaleX())));
            if (u > 1.0 or u < -1.0) {
                return @splat(1.0);
            }

            const b = -trafo.rotation.r[1];

            const v = math.dot3(b, k / @as(Vec4f, @splat(trafo.scaleY())));
            if (v > 1.0 or v < -1.0) {
                return @splat(1.0);
            }

            const uv = Vec2f{ 0.5 * (u + 1.0), 0.5 * (v + 1.0) };
            return scene.propMaterial(entity, 0).visibility(ray.direction, normal, uv, sampler, scene);
        }

        return @splat(1.0);
    }

    pub fn sampleTo(p: Vec4f, trafo: Trafo, two_sided: bool, sampler: *Sampler) ?SampleTo {
        const uv = sampler.sample2D();
        return sampleToUv(p, uv, trafo, two_sided);
    }

    pub fn sampleToUv(p: Vec4f, uv: Vec2f, trafo: Trafo, two_sided: bool) ?SampleTo {
        const uv2 = @as(Vec2f, @splat(-2.0)) * uv + @as(Vec2f, @splat(1.0));
        const ls = Vec4f{ uv2[0], uv2[1], 0.0, 0.0 };
        const ws = trafo.objectToWorldPoint(ls);
        var wn = trafo.rotation.r[2];

        if (two_sided and math.dot3(wn, ws - p) > 0.0) {
            wn = -wn;
        }

        const axis = ro.offsetRay(ws, wn) - p;
        const sl = math.squaredLength3(axis);
        const t = @sqrt(sl);
        const dir = axis / @as(Vec4f, @splat(t));
        const c = -math.dot3(wn, dir);

        if (c < Dot_min) {
            return null;
        }

        const scale = trafo.scale();
        const area = 4.0 * scale[0] * scale[1];

        return SampleTo.init(
            dir,
            wn,
            .{ uv[0], uv[1], 0.0, 0.0 },
            trafo,
            sl / (c * area),
            t,
        );
    }

    pub fn sampleFrom(
        trafo: Trafo,
        two_sided: bool,
        sampler: *Sampler,
        uv: Vec2f,
        importance_uv: Vec2f,
    ) SampleFrom {
        const uv2 = @as(Vec2f, @splat(-2.0)) * uv + @as(Vec2f, @splat(1.0));
        const ls = Vec4f{ uv2[0], uv2[1], 0.0, 0.0 };
        const ws = trafo.objectToWorldPoint(ls);
        var wn = trafo.rotation.r[2];

        var dir = math.smpl.orientedHemisphereCosine(
            importance_uv,
            trafo.rotation.r[0],
            trafo.rotation.r[1],
            wn,
        );

        if (two_sided and sampler.sample1D() > 0.5) {
            wn = -wn;
            dir = -dir;
        }

        const scale = trafo.scale();
        const area = @as(f32, if (two_sided) 8.0 else 4.0) * (scale[0] * scale[1]);

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

    pub fn pdf(ray: Ray, trafo: Trafo, two_sided: bool) f32 {
        var c = -math.dot3(trafo.rotation.r[2], ray.direction);

        if (two_sided) {
            c = @fabs(c);
        }

        const scale = trafo.scale();
        const area = 4.0 * scale[0] * scale[1];

        const max_t = ray.maxT();
        const sl = max_t * max_t;
        return sl / (c * area);
    }
};
