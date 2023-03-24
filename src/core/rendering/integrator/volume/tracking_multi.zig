const Result = @import("result.zig").Result;
const tracking = @import("tracking.zig");
const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const shp = @import("../../../scene/shape/intersection.zig");
const Interface = @import("../../../scene/prop/interface.zig").Interface;
const Filter = @import("../../../image/texture/texture_sampler.zig").Filter;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const hlp = @import("../helper.zig");
const ro = @import("../../../scene/ray_offset.zig");

const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Multi = struct {
    pub fn integrate(ray: *Ray, throughput: Vec4f, isec: *Intersection, filter: ?Filter, sampler: *Sampler, worker: *Worker) Result {
        const interface = worker.interface_stack.top();
        const material = interface.material(worker.scene);

        const densesss = material.denseSSSOptimization();

        if (densesss) {
            isec.subsurface = false;
            if (!worker.intersectProp(isec.prop, ray, .All, &isec.geo)) {
                worker.interface_stack.pop();

                return .{
                    .li = @splat(4, @as(f32, 0.0)),
                    .tr = @splat(4, @as(f32, 1.0)),
                    .event = if (worker.intersectAndResolveMask(ray, filter, isec)) .Pass else .Abort,
                };
            }
        } else {
            const ray_max_t = ray.ray.maxT();
            ray.ray.setMaxT(std.math.min(ro.offsetF(worker.scene.propAabbIntersectP(interface.prop, ray.*) orelse ray_max_t), ray_max_t));
            if (!worker.intersectAndResolveMask(ray, filter, isec)) {
                return .{
                    .li = @splat(4, @as(f32, 0.0)),
                    .tr = @splat(4, @as(f32, 1.0)),
                    .event = .Abort,
                };
            }

            // This test is intended to catch corner cases where we actually left the scattering medium,
            // but the intersection point was too close to detect.
            var missed = false;
            if (!interface.matches(isec.*) or !isec.sameHemisphere(ray.ray.direction)) {
                const v = -ray.ray.direction;

                var tray = Ray.init(isec.offsetP(v), v, 0.0, ro.Ray_max_t, 0, 0.0, ray.time);
                var nisec = shp.Intersection{};
                if (worker.intersectProp(interface.prop, &tray, .Normal, &nisec)) {
                    missed = math.dot3(nisec.geo_n, v) <= 0.0;
                } else {
                    missed = true;
                }
            }

            if (missed) {
                worker.interface_stack.pop();
                return .{
                    .li = @splat(4, @as(f32, 0.0)),
                    .tr = @splat(4, @as(f32, 1.0)),
                    .event = .Pass,
                };
            }
        }

        const d = ray.ray.maxT();

        if (!material.scatteringVolume()) {
            // Basically the "glass" case
            const mu_a = material.collisionCoefficients(math.vec2fTo4f(interface.uv), filter, worker.scene).a;
            return .{
                .li = @splat(4, @as(f32, 0.0)),
                .tr = hlp.attenuation3(mu_a, d - ray.ray.minT()),
                .event = .Pass,
            };
        }

        if (material.volumetricTree()) |tree| {
            var local_ray = tracking.texturespaceRay(ray.*, interface.prop, worker);

            const srs = material.super().similarityRelationScale(ray.depth);

            var result = Result.initPass(@splat(4, @as(f32, 1.0)));

            if (material.emissive()) {
                while (local_ray.minT() < d) {
                    if (tree.intersect(&local_ray)) |tcm| {
                        var cm = tcm;
                        cm.minorant_mu_s *= srs;
                        cm.majorant_mu_s *= srs;

                        result = tracking.trackingHeteroEmission(local_ray, cm, material, srs, result.tr, throughput, filter, worker);
                        if (.Scatter == result.event) {
                            setScattering(isec, interface, ray.ray.point(result.t));
                            break;
                        }

                        if (.Absorb == result.event) {
                            ray.ray.setMaxT(result.t);
                            // This is in local space on purpose! Alas, the purpose was not commented...
                            isec.geo.p = local_ray.point(result.t);
                            return result;
                        }
                    }

                    local_ray.setMinMaxT(ro.offsetF(local_ray.maxT()), d);
                }
            } else {
                while (local_ray.minT() < d) {
                    if (tree.intersect(&local_ray)) |tcm| {
                        var cm = tcm;
                        cm.minorant_mu_s *= srs;
                        cm.majorant_mu_s *= srs;

                        result = tracking.trackingHetero(local_ray, cm, material, srs, result.tr, throughput, filter, worker);
                        if (.Scatter == result.event) {
                            setScattering(isec, interface, ray.ray.point(result.t));
                            break;
                        }
                    }

                    local_ray.setMinMaxT(ro.offsetF(local_ray.maxT()), d);
                }
            }

            if (math.allLess4(result.tr, tracking.Abort_epsilon4)) {
                result.event = .Abort;
            }

            if (.Pass == result.event and densesss) {
                worker.correctVolumeInterfaceStack(isec.volume_entry, isec.geo.p, ray.time);
            }

            return result;
        }

        if (material.emissive()) {
            const cce = material.collisionCoefficientsEmission(@splat(4, @as(f32, 0.0)), filter, worker.scene);

            const result = tracking.trackingEmission(ray.ray, cce, throughput, &worker.rng);
            if (.Scatter == result.event) {
                setScattering(isec, interface, ray.ray.point(result.t));
            } else if (.Absorb == result.event) {
                ray.ray.setMaxT(result.t);
            }

            return result;
        }

        const mu = material.collisionCoefficients(math.vec2fTo4f(interface.uv), filter, worker.scene); // material.super().cc;

        const result = tracking.tracking(ray.ray, mu, throughput, sampler);
        if (.Scatter == result.event) {
            setScattering(isec, interface, ray.ray.point(result.t));
        } else if (.Pass == result.event and densesss) {
            worker.correctVolumeInterfaceStack(isec.volume_entry, isec.geo.p, ray.time);
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
    pub fn create(self: Factory) Multi {
        _ = self;
        return .{};
    }
};
