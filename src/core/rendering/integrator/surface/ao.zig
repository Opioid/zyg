const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const sampler = @import("../../../sampler/sampler.zig");
const math = @import("base").math;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;

//const std = @import("std");

pub const AO = struct {
    pub const Settings = struct {
        num_samples: u32,
        radius: f32,
    };

    settings: Settings,

    sampler: sampler.Sampler,

    pub fn init(alloc: *Allocator, settings: Settings, max_samples_per_pixel: u32) !AO {
        const total_samples_per_pixel = settings.num_samples * max_samples_per_pixel;

        return AO{
            .settings = settings,
            .sampler = sampler.Sampler{ .Golden_ratio = try sampler.Golden_ratio.init(
                alloc,
                0,
                1,
                total_samples_per_pixel,
            ) },
        };
    }

    pub fn deinit(self: *AO, alloc: *Allocator) void {
        self.sampler.deinit(alloc);
    }

    pub fn startPixel(self: *AO) void {
        self.sampler.startPixel();
    }

    pub fn li(self: *AO, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        _ = ray;

        const num_samples_reciprocal = 1.0 / @intToFloat(f32, self.settings.num_samples);

        var result: f32 = 0.0;

        var occlusion_ray: Ray = undefined;

        occlusion_ray.ray.origin = isec.offsetP(isec.geo.geo_n);
        occlusion_ray.ray.setMaxT(self.settings.radius);

        var i = self.settings.num_samples;
        while (i > 0) : (i -= 1) {
            const sample = self.sampler.sample2D(&worker.worker.rng, 0);

            const ws = math.sample.oriented_hemisphere_cosine(sample, isec.geo.t, isec.geo.b, isec.geo.n);

            occlusion_ray.ray.setDirection(ws);

            if (!worker.worker.intersectP(&occlusion_ray)) {
                result += num_samples_reciprocal;
            }
        }

        return Vec4f.init4(result, result, result, 1.0);
    }
};

pub const Factory = struct {
    settings: AO.Settings,

    pub fn create(self: Factory, alloc: *Allocator, max_samples_per_pixel: u32) !AO {
        return try AO.init(alloc, self.settings, max_samples_per_pixel);
    }
};
