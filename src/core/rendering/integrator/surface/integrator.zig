const AO = @import("ao.zig").AO;

const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;

const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Integrator = union(enum) {
    AO: AO,

    pub fn li(self: *Integrator, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        return switch (self.*) {
            .AO => |*ao| ao.li(ray, isec, worker),
        };
    }
};
