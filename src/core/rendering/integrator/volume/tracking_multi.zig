const tracking = @import("tracking.zig");
const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const shp = @import("../../../scene/shape/intersection.zig");
const Result = shp.Result;
const Interface = @import("../../../scene/prop/interface.zig").Interface;
const Trafo = @import("../../../scene/composed_transformation.zig").ComposedTransformation;
const Material = @import("../../../scene/material/material.zig").Material;
const CC = @import("../../../scene/material/collision_coefficients.zig").CC;
const Filter = @import("../../../image/texture/texture_sampler.zig").Filter;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const hlp = @import("../helper.zig");
const ro = @import("../../../scene/ray_offset.zig");

const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Multi = struct {
    pub fn propTransmittance(
        comptime WorldSpace: bool,
        ray: math.Ray,
        trafo: Trafo,
        material: *const Material,
        cc: CC,
        prop: u32,
        depth: u32,
        filter: ?Filter,
        worker: *Worker,
    ) ?Vec4f {
        const d = ray.maxT();

        if (ro.offsetF(ray.minT()) >= d) {
            return @splat(4, @as(f32, 1.0));
        }

        if (material.heterogeneousVolume()) {
            const local_ray = if (WorldSpace) math.Ray.init(
                trafo.worldToObjectPoint(ray.origin),
                trafo.worldToObjectVector(ray.direction),
                ray.minT(),
                ray.maxT(),
            ) else ray;

            return tracking.transmittanceHetero(local_ray, material, prop, depth, filter, worker);
        }

        return hlp.attenuation3(cc.a + cc.s, d - ray.minT());
    }

    pub fn propScatter(
        comptime WorldSpace: bool,
        ray: math.Ray,
        trafo: Trafo,
        throughput: Vec4f,
        material: *const Material,
        cc: CC,
        prop: u32,
        depth: u32,
        filter: ?Filter,
        sampler: *Sampler,
        worker: *Worker,
    ) Result {
        const d = ray.maxT();

        if (!material.scatteringVolume()) {
            // Basically the "glass" case
            return Result.initPass(hlp.attenuation3(cc.a, d - ray.minT()));
        }

        if (material.volumetricTree()) |tree| {
            const os_ray = if (WorldSpace) math.Ray.init(
                trafo.worldToObjectPoint(ray.origin),
                trafo.worldToObjectVector(ray.direction),
                ray.minT(),
                ray.maxT(),
            ) else ray;

            var local_ray = tracking.rayObjectSpaceToTextureSpace(os_ray, prop, worker);

            const srs = material.super().similarityRelationScale(depth);

            var result = Result.initPass(@splat(4, @as(f32, 1.0)));

            if (material.emissive()) {
                while (local_ray.minT() < d) {
                    if (tree.intersect(&local_ray)) |tcm| {
                        var cm = tcm;
                        cm.minorant_mu_s *= srs;
                        cm.majorant_mu_s *= srs;

                        result = tracking.trackingHeteroEmission(local_ray, cm, material, srs, result.tr, throughput, filter, worker);
                        if (.Scatter == result.event) {
                            break;
                        }

                        if (.Absorb == result.event) {
                            // This is in local space on purpose! Alas, the purpose was not commented...
                            //   isec.geo.p = local_ray.point(result.t);
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
                            break;
                        }
                    }

                    local_ray.setMinMaxT(ro.offsetF(local_ray.maxT()), d);
                }
            }

            return result;
        }

        if (material.emissive()) {
            const cce = material.collisionCoefficientsEmission(@splat(4, @as(f32, 0.0)), filter, worker.scene);
            return tracking.trackingEmission(ray, cce, throughput, &worker.rng);
        }

        return tracking.tracking(ray, cc, throughput, sampler);
    }

    pub fn integrate(ray: *Ray, throughput: Vec4f, isec: *Intersection, filter: ?Filter, sampler: *Sampler, worker: *Worker) Result {
        const interface = worker.interface_stack.top();
        const material = interface.material(worker.scene);

        const dense_sss = material.denseSSSOptimization();

        if (dense_sss) {
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
                return Result.initPass(@splat(4, @as(f32, 1.0)));
            }
        }

        var result = integrateSingle(ray.*, throughput, interface, isec, filter, sampler, worker);

        if (math.allLess4(result.tr, tracking.Abort_epsilon4)) {
            result.event = .Abort;
        }

        if (.Scatter == result.event) {
            setScattering(isec, interface, ray.ray.point(result.t));
        }

        return result;
    }

    fn integrateSingle(
        ray: Ray,
        throughput: Vec4f,
        interface: Interface,
        isec: *Intersection,
        filter: ?Filter,
        sampler: *Sampler,
        worker: *Worker,
    ) Result {
        // return propScatter(
        //     true,
        //     ray.ray,
        //     isec.geo.trafo,
        //     throughput,
        //     interface.material(worker.scene),
        //     interface.cc,
        //     interface.prop,
        //     ray.depth,
        //     filter,
        //     sampler,
        //     worker,
        // );

        const material = interface.material(worker.scene);

        const d = ray.ray.maxT();

        if (!material.scatteringVolume()) {
            // Basically the "glass" case
            const mu_a = interface.cc.a;
            return Result.initPass(hlp.attenuation3(mu_a, d - ray.ray.minT()));
        }

        if (material.volumetricTree()) |tree| {
            const trafo = worker.scene.propTransformationAt(interface.prop, ray.time);

            const tray = math.Ray.init(
                trafo.worldToObjectPoint(ray.ray.origin),
                trafo.worldToObjectVector(ray.ray.direction),
                ray.ray.minT(),
                ray.ray.maxT(),
            );

            var local_ray = tracking.rayObjectSpaceToTextureSpace(tray, interface.prop, worker);

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
                            break;
                        }

                        if (.Absorb == result.event) {
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
                            break;
                        }
                    }

                    local_ray.setMinMaxT(ro.offsetF(local_ray.maxT()), d);
                }
            }

            return result;
        }

        if (material.emissive()) {
            const cce = material.collisionCoefficientsEmission(@splat(4, @as(f32, 0.0)), filter, worker.scene);
            return tracking.trackingEmission(ray.ray, cce, throughput, &worker.rng);
        }

        const mu = interface.cc;
        return tracking.tracking(ray.ray, mu, throughput, sampler);
    }

    fn setScattering(isec: *Intersection, interface: Interface, p: Vec4f) void {
        isec.prop = interface.prop;
        isec.geo.p = p;
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
