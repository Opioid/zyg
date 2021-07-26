const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;

const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const AO = struct {
    sampler: Sampler,

    pub fn li(self: *AO, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        _ = self;
        _ = ray;
        _ = isec;
        _ = worker;

        var occlusion_ray: Ray = undefined;

        occlusion_ray.ray.origin = isec.offsetP(isec.geo.geo_n); // isec.geo.p.add3(isec.geo.geo_n.mulScalar3(0.01));
        occlusion_ray.ray.setMinT(0.1);
        occlusion_ray.ray.setMaxT(1.0);

        const sample = self.sampler.sample2D(&worker.worker.rng);

        const ws = math.sample.oriented_hemisphere_cosine(sample, isec.geo.t, isec.geo.b, isec.geo.n);

        occlusion_ray.ray.setDirection(ws);

        //     std.debug.print("{}\n", .{occlusion_ray.ray.maxT()});

        if (worker.worker.intersect(&occlusion_ray, isec)) {
            return Vec4f.init1(0.0);
        } else {
            return Vec4f.init1(1.0);
        }

        //    return isec.geo.b.addScalar3(1.0).mulScalar3(0.5);
    }
};
