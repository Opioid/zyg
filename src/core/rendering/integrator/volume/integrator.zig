const Result = @import("result.zig").Result;
const tracking = @import("tracking.zig");

const multi = @import("tracking_multi.zig");
pub const Multi = multi.Multi;
pub const MultiFactory = multi.Factory;

const Ray = @import("../../../scene/ray.zig").Ray;
const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Worker = @import("../../../rendering/worker.zig").Worker;
const Interface = @import("../../../scene/prop/interface.zig").Interface;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const Filter = @import("../../../image/texture/texture_sampler.zig").Filter;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Integrator = union(enum) {
    Multi: Multi,

    pub fn integrate(
        self: *Integrator,
        vertex: *Vertex,
        filter: ?Filter,
        sampler: *Sampler,
        worker: *Worker,
    ) Result {
        return switch (self.*) {
            .Multi => Multi.integrate(vertex, filter, sampler, worker),
        };
    }

    pub fn transmittance(self: Integrator, ray: Ray, interface: Interface, filter: ?Filter, worker: *Worker) ?Vec4f {
        _ = self;
        return tracking.transmittance(ray, interface, filter, worker);
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
