const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const Worker = @import("../worker.zig").Worker;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const SampleTo = @import("sample.zig").To;
//const Filter = @import("../../image/texture/sampler.zig").Filter;
const scn = @import("../constants.zig");
const base = @import("base");
const RNG = base.rnd.Generator;
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

pub const DistantSphere = struct {
    pub fn intersect(ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        const n = trafo.rotation.r[2];
        const b = math.dot3(n, ray.direction);

        if (b > 0.0 or ray.maxT() < scn.Ray_max_t) {
            return false;
        }

        const radius = trafo.scaleX();
        const det = (b * b) - math.dot3(n, n) + (radius * radius);

        if (det <= 0.0) {
            return false;
        }

        const hit_t = scn.Almost_ray_max_t;

        ray.setMaxT(hit_t);

        isec.p = ray.point(hit_t);
        isec.geo_n = n;
        isec.t = trafo.rotation.r[0];
        isec.b = trafo.rotation.r[1];
        isec.n = n;

        const k = ray.direction - n;
        const sk = k / @splat(4, radius);

        isec.uv[0] = (math.dot3(isec.t, sk) + 1.0) * 0.5;
        isec.uv[1] = (math.dot3(isec.b, sk) + 1.0) * 0.5;

        isec.part = 0;

        return true;
    }

    pub fn intersectP(ray: Ray, trafo: Transformation) bool {
        const n = trafo.rotation.r[2];
        const b = math.dot3(n, ray.direction);

        if (b > 0.0 or ray.maxT() < scn.Ray_max_t) {
            return false;
        }

        const radius = trafo.scaleX();
        const det = (b * b) - math.dot3(n, n) + (radius * radius);

        return det > 0.0;
    }

    pub fn sampleTo(
        trafo: Transformation,
        extent: f32,
        sampler: *Sampler,
        rng: *RNG,
        sampler_d: usize,
    ) SampleTo {
        const r2 = sampler.sample2D(rng, sampler_d);
        const xy = math.smpl.diskConcentric(r2);

        const ls = Vec4f{ xy[0], xy[1], 0.0, 0.0 };
        const radius = trafo.scaleX();
        const ws = @splat(4, radius) * trafo.rotation.transformVector(ls);

        return SampleTo.init(
            math.normalize3(ws - trafo.rotation.r[2]),
            @splat(4, @as(f32, 0.0)),
            @splat(4, @as(f32, 0.0)),
            1.0 / extent,
            scn.Almost_ray_max_t,
        );
    }
};
