const Result = @import("result.zig").Result;
const tracking = @import("tracking.zig");

const multi = @import("tracking_multi.zig");
pub const Multi = multi.Multi;
pub const MultiFactory = multi.Factory;

const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../../rendering/worker.zig").Worker;
const intr = @import("../../../scene/prop/interface.zig");
const Interface = intr.Interface;
const Stack = intr.Stack;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const Filter = @import("../../../image/texture/texture_sampler.zig").Filter;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Integrator = union(enum) {
    Multi: Multi,

    pub fn integrate(
        self: Integrator,
        ray: *Ray,
        throughput: Vec4f,
        isec: *Intersection,
        filter: ?Filter,
        sampler: *Sampler,
        worker: *Worker,
    ) Result {
        return switch (self) {
            .Multi => Multi.integrate(ray, throughput, isec, filter, sampler, worker),
        };
    }

    pub fn transmittance(self: Integrator, ray: Ray, stack: *const Stack, filter: ?Filter, worker: *Worker) ?Vec4f {
        _ = self;
        return tracking.transmittance(ray, stack, filter, worker);
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
