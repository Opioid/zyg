const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const Worker = @import("../worker.zig").Worker;
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

pub const Rectangle = struct {
    pub fn intersect(ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];

            const u = math.dot3(t, k / @splat(4, trafo.scaleX()));
            if (u > 1.0 or u < -1.0) {
                return false;
            }

            const b = -trafo.rotation.r[1];

            const v = math.dot3(b, k / @splat(4, trafo.scaleY()));
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

    pub fn intersectP(ray: Ray, trafo: Transformation) bool {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];

            const u = math.dot3(t, k / @splat(4, trafo.scaleX()));
            if (u > 1.0 or u < -1.0) {
                return false;
            }

            const b = -trafo.rotation.r[1];

            const v = math.dot3(b, k / @splat(4, trafo.scaleY()));
            if (v > 1.0 or v < -1.0) {
                return false;
            }

            return true;
        }

        return false;
    }

    pub fn visibility(
        ray: Ray,
        trafo: Transformation,
        entity: usize,
        filter: ?Filter,
        worker: Worker,
    ) ?Vec4f {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];

            const u = math.dot3(t, k / @splat(4, trafo.scaleX()));
            if (u > 1.0 or u < -1.0) {
                return @splat(4, @as(f32, 1.0));
            }

            const b = -trafo.rotation.r[1];

            const v = math.dot3(b, k / @splat(4, trafo.scaleY()));
            if (v > 1.0 or v < -1.0) {
                return @splat(4, @as(f32, 1.0));
            }

            const uv = Vec2f{ 0.5 * (u + 1.0), 0.5 * (v + 1.0) };
            return worker.scene.propMaterial(entity, 0).visibility(ray.direction, normal, uv, filter, worker);
        }

        return @splat(4, @as(f32, 1.0));
    }

    pub fn sampleTo(
        p: Vec4f,
        trafo: Transformation,
        area: f32,
        two_sided: bool,
        sampler: *Sampler,
        rng: *RNG,
        sampler_d: usize,
    ) ?SampleTo {
        const uv = sampler.sample2D(rng, sampler_d);
        return sampleToUv(p, uv, trafo, area, two_sided);
    }

    pub fn sampleFrom(
        trafo: Transformation,
        area: f32,
        two_sided: bool,
        sampler: *Sampler,
        rng: *RNG,
        sampler_d: usize,
        importance_uv: Vec2f,
    ) ?SampleFrom {
        const uv = sampler.sample2D(rng, sampler_d);
        return sampleFromUv(uv, trafo, area, two_sided, sampler, rng, sampler_d, importance_uv);
    }

    pub fn sampleToUv(
        p: Vec4f,
        uv: Vec2f,
        trafo: Transformation,
        area: f32,
        two_sided: bool,
    ) ?SampleTo {
        const uv2 = @splat(2, @as(f32, -2.0)) * uv + @splat(2, @as(f32, 1.0));
        const ls = Vec4f{ uv2[0], uv2[1], 0.0, 0.0 };
        const ws = trafo.objectToWorldPoint(ls);
        var wn = trafo.rotation.r[2];

        if (two_sided and math.dot3(wn, ws - p) > 0.0) {
            wn = -wn;
        }

        const axis = ro.offsetRay(ws, wn) - p;
        const sl = math.squaredLength3(axis);
        const t = @sqrt(sl);
        const dir = axis / @splat(4, t);
        const c = -math.dot3(wn, dir);

        if (c < Dot_min) {
            return null;
        }

        return SampleTo.init(dir, wn, .{ uv[0], uv[1], 0.0, 0.0 }, sl / (c * area), t);
    }

    pub fn sampleFromUv(
        uv: Vec2f,
        trafo: Transformation,
        area: f32,
        two_sided: bool,
        sampler: *Sampler,
        rng: *RNG,
        sampler_d: usize,
        importance_uv: Vec2f,
    ) ?SampleFrom {
        const uv2 = @splat(2, @as(f32, -2.0)) * uv + @splat(2, @as(f32, 1.0));
        const ls = Vec4f{ uv2[0], uv2[1], 0.0, 0.0 };
        const ws = trafo.objectToWorldPoint(ls);
        var wn = trafo.rotation.r[2];

        var dir = math.smpl.orientedHemisphereCosine(importance_uv, trafo.rotation.r[0], trafo.rotation.r[1], wn);

        if (two_sided and sampler.sample1D(rng, sampler_d) > 0.5) {
            wn = -wn;
            dir = -dir;
        }

        return SampleFrom.init(ro.offsetRay(ws, wn), wn, dir, uv, importance_uv, 1.0 / (std.math.pi * area));
    }

    pub fn pdf(ray: Ray, trafo: Transformation, area: f32, two_sided: bool) f32 {
        const n = trafo.rotation.r[2];

        var c = -math.dot3(n, ray.direction);

        if (two_sided) {
            c = @fabs(c);
        }

        const max_t = ray.maxT();
        const sl = max_t * max_t;
        return sl / (c * area);
    }
};
