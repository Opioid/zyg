const tracking = @import("tracking.zig");
const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Worker = @import("../../worker.zig").Worker;
const shp = @import("../../../scene/shape/intersection.zig");
const Intersection = shp.Intersection;
const Volume = shp.Volume;
const Interface = @import("../../../scene/prop/interface.zig").Interface;
const Trafo = @import("../../../scene/composed_transformation.zig").ComposedTransformation;
const Material = @import("../../../scene/material/material.zig").Material;
const CC = @import("../../../scene/material/collision_coefficients.zig").CC;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const hlp = @import("../helper.zig");
const ro = @import("../../../scene/ray_offset.zig");

const math = @import("base").math;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Multi = struct {
    pub fn propTransmittance(
        ray: Ray,
        material: *const Material,
        cc: CC,
        prop: u32,
        depth: u32,
        sampler: *Sampler,
        worker: *Worker,
    ) ?Vec4f {
        const d = ray.maxT();

        if (ro.offsetF(ray.minT()) >= d) {
            return @as(Vec4f, @splat(1.0));
        }

        if (material.heterogeneousVolume()) {
            return tracking.transmittanceHetero(ray, material, prop, depth, sampler, worker);
        }

        return hlp.attenuation3(cc.a + cc.s, d - ray.minT());
    }

    pub fn propScatter(
        ray: Ray,
        throughput: Vec4f,
        material: *const Material,
        cc: CC,
        prop: u32,
        depth: u32,
        sampler: *Sampler,
        worker: *Worker,
    ) Volume {
        const d = ray.maxT();

        if (!material.scatteringVolume()) {
            // Basically the "glass" case
            return Volume.initPass(hlp.attenuation3(cc.a, d - ray.minT()));
        }

        if (math.allLess4(throughput, tracking.Abort_epsilon4)) {
            return Volume.initPass(@splat(1.0));
        }

        if (material.volumetricTree()) |tree| {
            var local_ray = tracking.objectToTextureRay(ray, prop, worker);

            const srs = material.super().similarityRelationScale(depth);

            var result = Volume.initPass(@splat(1.0));

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
                            sampler,
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
                            sampler,
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
            const cce = material.collisionCoefficientsEmission(@splat(0.0), sampler, worker.scene);
            return tracking.trackingEmission(ray, cce, throughput, &worker.rng);
        }

        return tracking.tracking(ray, cc, throughput, sampler);
    }

    pub fn integrate(
        vertex: *Vertex,
        throughput: Vec4f,
        isec: *Intersection,
        sampler: *Sampler,
        worker: *Worker,
    ) bool {
        const interface = worker.interface_stack.top();
        const material = interface.material(worker.scene);

        if (material.denseSSSOptimization()) {
            if (!worker.propIntersect(isec.prop, vertex, .Normal, isec)) {
                return false;
            }
        } else {
            const ray_max_t = vertex.ray.maxT();
            const limit = worker.scene.propAabbIntersectP(interface.prop, vertex.ray) orelse ray_max_t;
            vertex.ray.setMaxT(math.min(ro.offsetF(limit), ray_max_t));
            if (!worker.intersectAndResolveMask(vertex, sampler, isec)) {
                vertex.ray.setMinMaxT(vertex.ray.maxT(), ray_max_t);
                return false;
            }

            // This test is intended to catch corner cases where we actually left the scattering medium,
            // but the intersection point was too close to detect.
            var missed = false;
            if (!interface.matches(isec.*) or !isec.sameHemisphere(vertex.ray.direction)) {
                const v = -vertex.ray.direction;

                var tvertex = Vertex.init(isec.offsetP(v), v, 0.0, ro.Ray_max_t, 0, 0.0, vertex.time);
                var nisec: Intersection = undefined;
                if (worker.propIntersect(interface.prop, &tvertex, .Normal, &nisec)) {
                    missed = math.dot3(nisec.geo_n, v) <= 0.0;
                } else {
                    missed = true;
                }
            }

            if (missed) {
                vertex.ray.setMinMaxT(math.min(ro.offsetF(vertex.ray.maxT()), ray_max_t), ray_max_t);
                return false;
            }
        }

        const tray = if (material.heterogeneousVolume())
            worker.scene.propTransformationAt(interface.prop, vertex.time).worldToObjectRay(vertex.ray)
        else
            vertex.ray;

        var result = propScatter(
            tray,
            throughput,
            material,
            interface.cc,
            interface.prop,
            vertex.depth,
            sampler,
            worker,
        );

        if (.Scatter == result.event) {
            isec.prop = interface.prop;
            isec.p = vertex.ray.point(result.t);
            isec.part = interface.part;
        }

        isec.setVolume(result);
        return true;
    }
};
