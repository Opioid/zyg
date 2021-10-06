const Result = @import("result.zig").Result;
const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const Filter = @import("../../../image/texture/sampler.zig").Filter;
const hlp = @import("../helper.zig");
const scn = @import("../../../scene/constants.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Multi = struct {
    pub fn integrate(
        ray: *Ray,
        isec: *Intersection,
        filter: ?Filter,
        worker: *Worker,
    ) Result {
        if (!worker.super.intersectAndResolveMask(ray, filter, isec)) {
            return .{
                .li = @splat(4, @as(f32, 0.0)),
                .tr = @splat(4, @as(f32, 1.0)),
                .event = .Abort,
            };
        }

        const interface = worker.super.interface_stack.top();

        const d = ray.ray.maxT();

        // This test is intended to catch corner cases where we actually left the scattering medium,
        // but the intersection point was too close to detect.
        var missed = false;

        if (scn.Almost_ray_max_t <= d) {
            missed = true;
        } else if (!interface.matches(isec.*) or !isec.sameHemisphere(ray.ray.direction)) {}

        if (missed) {
            worker.super.interface_stack.pop();

            return .{
                .li = @splat(4, @as(f32, 0.0)),
                .tr = @splat(4, @as(f32, 1.0)),
                .event = .Pass,
            };
        }

        const material = interface.material(worker.super);

        if (!material.isScatteringVolume()) {
            // Basically the "glass" case
            const mu_a = material.collisionCoefficients(interface.uv, filter, worker.super).a;
            return .{
                .li = @splat(4, @as(f32, 0.0)),
                .tr = hlp.attenuation3(mu_a, d - ray.ray.minT()),
                .event = .Pass,
            };
        }

        return .{
            .li = @splat(4, @as(f32, 0.0)),
            .tr = @splat(4, @as(f32, 1.0)),
            .event = .Abort,
        };
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
