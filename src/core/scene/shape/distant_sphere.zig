const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const Worker = @import("../worker.zig").Worker;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
//const Filter = @import("../../image/texture/sampler.zig").Filter;
const scn = @import("../constants.zig");

const base = @import("base");
const RNG = base.rnd.Generator;
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

pub const DistantSphere = struct {
    pub fn intersect(ray: *Ray, trafo: Trafo, isec: *Intersection) bool {
        const n = trafo.rotation.r[2];
        const b = math.dot3(n, ray.direction);

        if (b > 0.0 or ray.maxT() < scn.Ray_max_t) {
            return false;
        }

        const radius = trafo.scaleX();
        const det = (b * b) - math.dot3(n, n) + (radius * radius);

        if (det >= 0.0) {
            isec.p = @splat(4, @as(f32, scn.Almost_ray_max_t)) * ray.direction;
            isec.geo_n = n;
            isec.t = trafo.rotation.r[0];
            isec.b = trafo.rotation.r[1];
            isec.n = n;

            const k = ray.direction - n;
            const sk = k / @splat(4, radius);

            isec.uv[0] = (math.dot3(isec.t, sk) + 1.0) * 0.5;
            isec.uv[1] = (math.dot3(isec.b, sk) + 1.0) * 0.5;

            isec.part = 0;
            isec.primitive = 0;

            ray.setMaxT(scn.Almost_ray_max_t);

            return true;
        }

        return false;
    }

    pub fn intersectP(ray: Ray, trafo: Trafo) bool {
        const n = trafo.rotation.r[2];
        const b = math.dot3(n, ray.direction);

        if (b > 0.0 or ray.maxT() < scn.Ray_max_t) {
            return false;
        }

        const radius = trafo.scaleX();
        const det = (b * b) - math.dot3(n, n) + (radius * radius);

        return det >= 0.0;
    }

    pub fn sampleTo(trafo: Trafo, extent: f32, sampler: *Sampler, rng: *RNG) SampleTo {
        const r2 = sampler.sample2D(rng);
        const xy = math.smpl.diskConcentric(r2);

        const ls = Vec4f{ xy[0], xy[1], 0.0, 0.0 };
        const radius = trafo.scaleX();
        const ws = @splat(4, radius) * trafo.rotation.transformVector(ls);

        return SampleTo.init(
            math.normalize3(ws - trafo.rotation.r[2]),
            @splat(4, @as(f32, 0.0)),
            @splat(4, @as(f32, 0.0)),
            trafo,
            1.0 / extent,
            scn.Almost_ray_max_t,
        );
    }

    pub fn sampleFrom(trafo: Trafo, extent: f32, uv: Vec2f, importance_uv: Vec2f, bounds: AABB) SampleFrom {
        const xy = math.smpl.diskConcentric(uv);

        const ls = Vec4f{ xy[0], xy[1], 0.0, 0.0 };
        const radius = trafo.scaleX();
        const ws = @splat(4, radius) * trafo.rotation.transformVector(ls);

        const dir = math.normalize3(trafo.rotation.r[2] - ws);

        const ls_bounds = bounds.transformTransposed(trafo.rotation);
        const ls_extent = ls_bounds.extent();
        const ls_rect = (importance_uv - @splat(2, @as(f32, 0.5))) * Vec2f{ ls_extent[0], ls_extent[1] };
        const photon_rect = trafo.rotation.transformVector(.{ ls_rect[0], ls_rect[1], 0.0, 0.0 });

        const offset = @splat(4, ls_extent[2]) * dir;
        const p = ls_bounds.position() - offset + photon_rect;

        return SampleFrom.init(
            p,
            trafo.rotation.r[2],
            dir,
            .{ uv[0], uv[1], 0.0, 0.0 },
            importance_uv,
            trafo,
            1.0 / (extent * ls_extent[0] * ls_extent[1]),
        );
    }
};
