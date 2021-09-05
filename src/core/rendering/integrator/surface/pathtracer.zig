const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const sampler = @import("../../../sampler/sampler.zig");
const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Pathtracer = struct {
    pub const Settings = struct {
        num_samples: u32,
        min_bounces: u32,
        max_bounces: u32,
    };

    settings: Settings,

    sampler: sampler.Sampler,

    const Self = @This();

    pub fn init(alloc: *Allocator, settings: Settings, max_samples_per_pixel: u32) !Self {
        _ = alloc;
        _ = max_samples_per_pixel;

        //const total_samples_per_pixel = settings.num_samples * max_samples_per_pixel;

        return Pathtracer{
            .settings = settings,
            .sampler = sampler.Sampler{ .Random = .{} },
        };
    }

    pub fn deinit(self: *Self, alloc: *Allocator) void {
        self.sampler.deinit(alloc);
    }

    pub fn startPixel(self: *Self) void {
        self.sampler.startPixel();
    }

    pub fn li(self: *Self, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        const num_samples_reciprocal = 1.0 / @intToFloat(f32, self.settings.num_samples);

        var result = Vec4f.init1(0.0);

        var i = self.settings.num_samples;
        while (i > 0) : (i -= 1) {
            var split_ray = ray.*;
            var split_isec = isec.*;

            result.addAssign4(self.integrate(&split_ray, &split_isec, worker).mulScalar4(num_samples_reciprocal));
        }

        return result;
    }

    fn integrate(self: *Self, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        _ = self;
        _ = ray;

        const wo = ray.ray.direction.neg3();

        const mat_sample = isec.sample(wo, ray.*, &worker.super);

        return mat_sample.super().radiance;
    }
};

pub const Factory = struct {
    settings: Pathtracer.Settings = .{ .num_samples = 1, .radius = 1.0 },

    pub fn create(self: Factory, alloc: *Allocator, max_samples_per_pixel: u32) !Pathtracer {
        return try Pathtracer.init(alloc, self.settings, max_samples_per_pixel);
    }
};
