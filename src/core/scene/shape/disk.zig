const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
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

pub const Disk = struct {
    pub fn intersect(ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const l = math.dot3(k, k);
            const radius = trafo.scaleX();

            if (l <= radius * radius) {
                const t = -trafo.rotation.r[0];
                const b = -trafo.rotation.r[1];

                const sk = k / @splat(4, radius);
                const uv_scale = 0.5 * trafo.scaleZ();

                isec.p = p;
                isec.t = t;
                isec.b = b;
                isec.n = normal;
                isec.geo_n = normal;
                isec.uv = .{
                    (math.dot3(t, sk) + 1.0) * uv_scale,
                    (math.dot3(b, sk) + 1.0) * uv_scale,
                };
                isec.part = 0;

                ray.setMaxT(hit_t);
                return true;
            }
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
            const l = math.dot3(k, k);
            const radius = trafo.scaleX();

            if (l <= radius * radius) {
                return true;
            }
        }

        return false;
    }

    pub fn visibility(
        ray: Ray,
        trafo: Transformation,
        entity: usize,
        filter: ?Filter,
        scene: Scene,
    ) ?Vec4f {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t > ray.minT() and hit_t < ray.maxT()) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const l = math.dot3(k, k);
            const radius = trafo.scaleX();

            if (l <= radius * radius) {
                const t = -trafo.rotation.r[0];
                const b = -trafo.rotation.r[1];

                const sk = k / @splat(4, radius);
                const uv_scale = 0.5 * trafo.scaleZ();

                const uv = Vec2f{
                    (math.dot3(t, sk) + 1.0) * uv_scale,
                    (math.dot3(b, sk) + 1.0) * uv_scale,
                };

                return scene.propMaterial(entity, 0).visibility(ray.direction, normal, uv, filter, scene);
            }
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
    ) ?SampleTo {
        const r2 = sampler.sample2D(rng);
        const xy = math.smpl.diskConcentric(r2);

        const ls = Vec4f{ xy[0], xy[1], 0.0, 0.0 };
        const ws = trafo.position + @splat(4, trafo.scaleX()) * trafo.rotation.transformVector(ls);
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

        return SampleTo.init(dir, wn, @splat(4, @as(f32, 0.0)), sl / (c * area), t);
    }

    pub fn sampleFrom(
        trafo: Transformation,
        area: f32,
        cos_a: f32,
        two_sided: bool,
        sampler: *Sampler,
        rng: *RNG,
        uv: Vec2f,
        importance_uv: Vec2f,
    ) ?SampleFrom {
        const xy = math.smpl.diskConcentric(uv);

        const ls = Vec4f{ xy[0], xy[1], 0.0, 0.0 };
        const ws = trafo.position + @splat(4, trafo.scaleX()) * trafo.rotation.transformVector(ls);
        var wn = trafo.rotation.r[2];

        if (cos_a < Dot_min) {
            var dir = math.smpl.orientedHemisphereCosine(importance_uv, trafo.rotation.r[0], trafo.rotation.r[1], wn);

            if (two_sided and sampler.sample1D(rng) > 0.5) {
                wn = -wn;
                dir = -dir;
            }

            return SampleFrom.init(ro.offsetRay(ws, wn), wn, dir, .{ 0.0, 0.0 }, importance_uv, 1.0 / (std.math.pi * area));
        } else {
            var dir = math.smpl.orientedConeUniform(importance_uv, cos_a, trafo.rotation.r[0], trafo.rotation.r[1], wn);

            const pdf = math.smpl.conePdfUniform(cos_a);

            if (two_sided and sampler.sample1D(rng) > 0.5) {
                wn = -wn;
                dir = -dir;
            }

            return SampleFrom.init(ro.offsetRay(ws, wn), wn, dir, .{ 0.0, 0.0 }, importance_uv, pdf / area);
        }
    }
};
