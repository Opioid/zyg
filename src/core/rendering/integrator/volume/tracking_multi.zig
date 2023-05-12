const tracking = @import("tracking.zig");
const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const shp = @import("../../../scene/shape/intersection.zig");
const Volume = shp.Volume;
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
        ray: math.Ray,
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
            return tracking.transmittanceHetero(ray, material, prop, depth, filter, worker);
        }

        return hlp.attenuation3(cc.a + cc.s, d - ray.minT());
    }

    pub fn propScatter(
        ray: math.Ray,
        throughput: Vec4f,
        material: *const Material,
        cc: CC,
        prop: u32,
        depth: u32,
        filter: ?Filter,
        sampler: *Sampler,
        worker: *Worker,
    ) Volume {
        const d = ray.maxT();

        if (!material.scatteringVolume()) {
            // Basically the "glass" case
            return Volume.initPass(hlp.attenuation3(cc.a, d - ray.minT()));
        }

        if (math.allLess4(throughput, tracking.Abort_epsilon4)) {
            return Volume.initPass(@splat(4, @as(f32, 1.0)));
        }

        if (material.volumetricTree()) |tree| {
            var local_ray = tracking.objectToTextureRay(ray, prop, worker);

            const srs = material.super().similarityRelationScale(depth);

            var result = Volume.initPass(@splat(4, @as(f32, 1.0)));

            if (material.emissive()) {
                while (local_ray.minT() < d) {
                    if (tree.intersect(&local_ray)) |cm| {
                        result = tracking.trackingHeteroEmission(
                            local_ray,
                            cm,
                            material,
                            srs,
                            result.tr,
                            throughput,
                            filter,
                            worker,
                        );

                        if (.Scatter == result.event) {
                            break;
                        }

                        if (.Absorb == result.event) {
                            result.uvw = local_ray.point(result.t);
                            return result;
                        }
                    }

                    local_ray.setMinMaxT(ro.offsetF(local_ray.maxT()), d);
                }
            } else {
                while (local_ray.minT() < d) {
                    if (tree.intersect(&local_ray)) |cm| {
                        result = tracking.trackingHetero(
                            local_ray,
                            cm,
                            material,
                            srs,
                            result.tr,
                            throughput,
                            filter,
                            worker,
                        );

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

    pub fn integrate(
        ray: *Ray,
        throughput: Vec4f,
        isec: *Intersection,
        filter: ?Filter,
        sampler: *Sampler,
        worker: *Worker,
    ) bool {
        const interface = worker.interface_stack.top();
        const material = interface.material(worker.scene);

        if (material.denseSSSOptimization()) {
            if (!worker.intersectProp(isec.prop, ray, .Normal, &isec.geo)) {
                return false;
            }
        } else {
            const ray_max_t = ray.ray.maxT();
            const limit = worker.scene.propAabbIntersectP(interface.prop, ray.*) orelse ray_max_t;
            ray.ray.setMaxT(std.math.min(ro.offsetF(limit), ray_max_t));
            if (!worker.intersectAndResolveMask(ray, filter, isec)) {
                ray.ray.setMinMaxT(ray.ray.maxT(), ray_max_t);
                return false;
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
                ray.ray.setMinMaxT(std.math.min(ro.offsetF(ray.ray.maxT()), ray_max_t), ray_max_t);
                return false;
            }
        }

        const tray = if (material.heterogeneousVolume())
            worker.scene.propTransformationAt(interface.prop, ray.time).worldToObjectRay(ray.ray)
        else
            ray.ray;

        var result = propScatter(
            tray,
            throughput,
            material,
            interface.cc,
            interface.prop,
            ray.depth,
            filter,
            sampler,
            worker,
        );

        if (.Scatter == result.event) {
            isec.prop = interface.prop;
            isec.geo.p = ray.ray.point(result.t);
            isec.geo.part = interface.part;
        }

        isec.volume = result;
        return true;
    }
};
