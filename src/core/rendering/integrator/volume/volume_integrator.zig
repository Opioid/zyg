const tracking = @import("tracking.zig");
const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Probe = Vertex.Probe;
const Worker = @import("../../worker.zig").Worker;
const int = @import("../../../scene/shape/intersection.zig");
const Fragment = int.Fragment;
const Volume = int.Volume;
const Interface = @import("../../../scene/prop/interface.zig").Interface;
const Trafo = @import("../../../scene/composed_transformation.zig").ComposedTransformation;
const Material = @import("../../../scene/material/material.zig").Material;
const CC = @import("../../../scene/material/collision_coefficients.zig").CC;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const hlp = @import("../helper.zig");
const ro = @import("../../../scene/ray_offset.zig");

const math = @import("base").math;
const Frame = math.Frame;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Integrator = struct {
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

    pub fn integrate(vertex: *Vertex, frag: *Fragment, sampler: *Sampler, worker: *Worker) bool {
        const interface = vertex.interfaces.top();
        const material = interface.material(worker.scene);

        const ray_max_t = vertex.probe.ray.maxT();
        const limit = worker.scene.propAabbIntersectP(interface.prop, vertex.probe.ray) orelse ray_max_t;
        vertex.probe.ray.setMaxT(math.min(ro.offsetF(limit), ray_max_t));
        if (!worker.intersectAndResolveMask(&vertex.probe, frag, sampler)) {
            vertex.probe.ray.setMinMaxT(vertex.probe.ray.maxT(), ray_max_t);
            return false;
        }

        // This test is intended to catch corner cases where we actually left the scattering medium,
        // but the intersection point was too close to detect.
        var missed = false;
        if (!interface.matches(frag) or !frag.sameHemisphere(vertex.probe.ray.direction)) {
            const v = -vertex.probe.ray.direction;

            var tprobe = vertex.probe.clone(Ray.init(frag.offsetP(v), v, 0.0, ro.Ray_max_t));
            var tisec: Fragment = undefined;
            if (worker.propIntersect(interface.prop, &tprobe, &tisec)) {
                worker.propInterpolateFragment(interface.prop, &tprobe, .PositionAndNormal, &tisec);
                missed = math.dot3(tisec.geo_n, v) <= 0.0;
            } else {
                missed = true;
            }
        }

        if (missed) {
            vertex.probe.ray.setMinMaxT(math.min(ro.offsetF(vertex.probe.ray.maxT()), ray_max_t), ray_max_t);
            return false;
        }

        const tray = if (material.heterogeneousVolume())
            worker.scene.propTransformationAt(interface.prop, vertex.probe.time).worldToObjectRay(vertex.probe.ray)
        else
            vertex.probe.ray;

        const result = propScatter(
            tray,
            vertex.throughput,
            material,
            vertex.interfaces.topCC(),
            interface.prop,
            vertex.probe.depth.volume,
            sampler,
            worker,
        );

        if (.Pass != result.event) {
            frag.prop = interface.prop;
            frag.part = interface.part;
            frag.p = vertex.probe.ray.point(result.t);
            frag.uvw = result.uvw;
        }

        frag.setVolume(result);
        return true;
    }

    pub fn integrateSSS(vertex: *Vertex, frag: *Fragment, sampler: *Sampler, max_depth: u32, worker: *Worker) bool {
        const interface = vertex.interfaces.top();
        const material = interface.material(worker.scene);

        const cc = vertex.interfaces.topCC();
        const g = material.super().volumetric_anisotropy;

        for (0..max_depth) |_| {
            if (!worker.propIntersect(interface.prop, &vertex.probe, frag)) {
                return false;
            }

            const tray = if (material.heterogeneousVolume())
                worker.scene.propTransformationAt(interface.prop, vertex.probe.time).worldToObjectRay(vertex.probe.ray)
            else
                vertex.probe.ray;

            var result = propScatter(
                tray,
                vertex.throughput,
                material,
                cc,
                interface.prop,
                vertex.probe.depth.volume,
                sampler,
                worker,
            );

            if (.Scatter != result.event) {
                worker.propInterpolateFragment(frag.prop, &vertex.probe, .All, frag);

                if (frag.sameHemisphere(vertex.probe.ray.direction)) {
                    vertex.interfaces.pop();
                    result.event = .ExitSSS;
                }

                frag.setVolume(result);

                return true;
            }

            vertex.throughput_old = vertex.throughput;
            vertex.throughput *= result.tr;

            // const rr = hlp.russianRoulette(vertex.throughput, vertex.throughput_old, sampler.sample1D()) orelse return false;
            // vertex.throughput /= @splat(rr);

            // const sum_weight = vertex.throughput[0] + vertex.throughput[1] + vertex.throughput[2];

            // const epsilon = 1e-6;
            // if (sum_weight < epsilon) {
            //     return false; // Path went extinct.
            // }

            // const avg_weights = sum_weight / 3.0;
            // const russian_roulette = 0.1;
            // if (avg_weights <= russian_roulette) {
            //     if (sampler.sample1D() * russian_roulette < avg_weights) {
            //         vertex.throughput *= @splat(russian_roulette / avg_weights);
            //     } else {
            //         return false;
            //     }
            // }

            const frame = Frame.init(vertex.probe.ray.direction);

            const r2 = sampler.sample2D();

            var cos_theta: f32 = undefined;
            if (@abs(g) < 0.001) {
                cos_theta = 1.0 - 2.0 * r2[0];
            } else {
                const gg = g * g;
                const sqr = (1.0 - gg) / (1.0 - g + 2.0 * g * r2[0]);
                cos_theta = (1.0 + gg - sqr * sqr) / (2.0 * g);
            }

            const sin_theta = @sqrt(math.max(0.0, 1.0 - cos_theta * cos_theta));
            const phi = r2[1] * (2.0 * std.math.pi);

            const wil = math.smpl.sphereDirection(sin_theta, cos_theta, phi);
            const wi = frame.frameToWorld(wil);

            vertex.probe.ray.origin = vertex.probe.ray.point(result.t);
            vertex.probe.ray.setDirection(wi, ro.Ray_max_t);
        }

        return false;
    }
};
