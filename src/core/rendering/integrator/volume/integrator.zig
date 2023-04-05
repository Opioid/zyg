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
const Trafo = @import("../../../scene/composed_transformation.zig").ComposedTransformation;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const Material = @import("../../../scene/material/material.zig").Material;
const CC = @import("../../../scene/material/collision_coefficients.zig").CC;
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

    pub fn propTransmittance(
        self: Integrator,
        ray: math.Ray,
        trafo: Trafo,
        material: *const Material,
        cc: CC,
        prop: u32,
        depth: u32,
        filter: ?Filter,
        worker: *Worker,
    ) ?Vec4f {
        _ = self;
        return tracking.propTransmittance(ray, trafo, material, cc, prop, depth, filter, worker);
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
