const Result = @import("result.zig").Result;
const tracking = @import("tracking.zig");

const multi = @import("tracking_multi.zig");
pub const Multi = multi.Multi;
pub const MultiFactory = multi.Factory;

const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const SceneWorker = @import("../../../scene/worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const Filter = @import("../../../image/texture/texture_sampler.zig").Filter;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Integrator = union(enum) {
    Multi: Multi,

    pub fn integrate(
        self: *Integrator,
        ray: *Ray,
        isec: *Intersection,
        filter: ?Filter,
        sampler: *Sampler,
        worker: *Worker,
    ) Result {
        return switch (self.*) {
            .Multi => Multi.integrate(ray, isec, filter, sampler, &worker.super),
        };
    }

    pub fn transmittance(self: Integrator, ray: *const Ray, filter: ?Filter, worker: *SceneWorker) ?Vec4f {
        _ = self;
        return tracking.transmittance(ray, filter, worker);
    }
};

pub const Factory = union(enum) {
    Multi: MultiFactory,

    pub fn create(self: Factory) Integrator {
        return switch (self) {
            .Multi => |m| Integrator{ .Multi = m.create() },
        };
    }
};
