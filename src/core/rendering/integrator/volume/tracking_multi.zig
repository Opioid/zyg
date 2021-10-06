const Result = @import("result.zig").Result;
const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const Filter = @import("../../../image/texture/sampler.zig").Filter;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Multi = struct {
    pub fn integrate(
        ray: *Ray,
        isec: *Intersection,
        filter: ?Filter,
        worker: *Worker,
    ) Result {
        _ = ray;
        _ = isec;
        _ = filter;
        _ = worker;

        return .{ .li = @splat(4, @as(f32, 0.0)), .tr = @splat(4, @as(f32, 1.0)), .event = .Abort };
    }
};

pub const Factory = struct {
    pub fn create(self: Factory, alloc: *Allocator, max_samples_per_pixel: u32) !Multi {
        _ = self;
        _ = alloc;
        _ = max_samples_per_pixel;
        return Multi{};
    }
};
