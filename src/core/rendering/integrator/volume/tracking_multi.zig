const Result = @import("result.zig").Result;
const tracking = @import("tracking.zig");
const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../../scene/worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const Interface = @import("../../../scene/prop/interface.zig").Interface;
const Filter = @import("../../../image/texture/sampler.zig").Filter;
const hlp = @import("../helper.zig");
const ro = @import("../../../scene/ray_offset.zig");
const scn = @import("../../../scene/constants.zig");
const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Multi = struct {
    pub fn integrate(
        ray: *Ray,
        isec: *Intersection,
        filter: ?Filter,
        worker: *Worker,
    ) Result {
        if (!worker.intersectAndResolveMask(ray, filter, isec)) {
            return .{
                .li = @splat(4, @as(f32, 0.0)),
                .tr = @splat(4, @as(f32, 1.0)),
                .event = .Abort,
            };
        }

        const interface = worker.interface_stack.top();

        const d = ray.ray.maxT();

        // This test is intended to catch corner cases where we actually left the scattering medium,
        // but the intersection point was too close to detect.
        var missed = false;

        if (scn.Almost_ray_max_t <= d) {
            missed = true;
        } else if (!interface.matches(isec.*) or !isec.sameHemisphere(ray.ray.direction)) {}

        if (missed) {
            worker.interface_stack.pop();

            return .{
                .li = @splat(4, @as(f32, 0.0)),
                .tr = @splat(4, @as(f32, 1.0)),
                .event = .Pass,
            };
        }

        const material = interface.material(worker.*);

        if (!material.scatteringVolume()) {
            // Basically the "glass" case
            const mu_a = material.collisionCoefficients(math.vec2fTo4f(interface.uv), filter, worker.*).a;
            return .{
                .li = @splat(4, @as(f32, 0.0)),
                .tr = hlp.attenuation3(mu_a, d - ray.ray.minT()),
                .event = .Pass,
            };
        }

        if (material.volumetricTree()) |tree| {
            var local_ray = tracking.texturespaceRay(ray.*, interface.prop, worker.*);

            const srs = material.super().similarityRelationScale(ray.depth);

            var result = Result.initPass(@splat(4, @as(f32, 1.0)));

            while (local_ray.minT() < d) {
                if (tree.intersect(&local_ray)) |tcm| {
                    var cm = tcm;
                    cm.minorant_mu_s *= srs;
                    cm.majorant_mu_s *= srs;

                    result = tracking.trackingHetero(local_ray, cm, material, srs, result.tr, filter, worker);
                    if (.Scatter == result.event) {
                        setScattering(isec, interface, ray.ray.point(result.t));
                        break;
                    }
                }

                local_ray.setMinT(ro.offsetF(local_ray.maxT()));
                local_ray.setMaxT(d);
            }

            if (!math.anyGreaterEqual3(result.tr, tracking.Abort_epsilon)) {
                result.event = .Abort;
            }

            return result;
        }

        if (material.emissive()) {
            const cce = material.collisionCoefficientsEmission(@splat(4, @as(f32, 0.0)), filter, worker.*);

            const result = tracking.trackingEmission(ray.ray, cce, &worker.rng);
            if (.Scatter == result.event) {
                setScattering(isec, interface, ray.ray.point(result.t));
            } else if (.Absorb == result.event) {
                ray.ray.setMaxT(result.t);
            }

            return result;
        }

        const mu = material.super().cc;

        const result = tracking.tracking(ray.ray, mu, &worker.rng);
        if (.Scatter == result.event) {
            setScattering(isec, interface, ray.ray.point(result.t));
        }

        return result;
    }

    fn setScattering(isec: *Intersection, interface: Interface, p: Vec4f) void {
        isec.prop = interface.prop;
        isec.geo.p = p;
        isec.geo.uv = interface.uv;
        isec.geo.part = interface.part;
        isec.subsurface = true;
    }
};

pub const Factory = struct {
    pub fn create(self: Factory, alloc: Allocator, max_samples_per_pixel: u32) !Multi {
        _ = self;
        _ = alloc;
        _ = max_samples_per_pixel;
        return Multi{};
    }
};
