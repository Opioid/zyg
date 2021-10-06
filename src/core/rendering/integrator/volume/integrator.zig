const Result = @import("result.zig").Result;

const multi = @import("tracking_multi.zig");
pub const Multi = multi.Multi;
pub const MultiFactory = multi.Factory;

const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const Filter = @import("../../../image/texture/sampler.zig").Filter;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Integrator = union(enum) {
    Multi: Multi,

    pub fn deinit(self: *Integrator, alloc: *Allocator) void {
        _ = self;
        _ = alloc;
    }

    pub fn integrate(
        self: *Integrator,
        ray: *Ray,
        isec: *Intersection,
        filter: ?Filter,
        worker: *Worker,
    ) Result {
        return switch (self.*) {
            .Multi => Multi.integrate(ray, isec, filter, worker),
        };
    }
};

pub const Factory = union(enum) {
    Multi: MultiFactory,

    pub fn create(self: Factory, alloc: *Allocator, max_samples_per_pixel: u32) !Integrator {
        return switch (self) {
            .Multi => |m| Integrator{ .Multi = try m.create(alloc, max_samples_per_pixel) },
        };
    }
};
