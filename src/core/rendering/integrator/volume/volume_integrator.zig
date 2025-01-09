const tracking = @import("tracking.zig");
const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Probe = Vertex.Probe;
const Worker = @import("../../worker.zig").Worker;
const int = @import("../../../scene/shape/intersection.zig");
const Fragment = int.Fragment;
const Volume = int.Volume;
const Medium = @import("../../../scene/prop/medium.zig").Medium;
const Trafo = @import("../../../scene/composed_transformation.zig").ComposedTransformation;
const Material = @import("../../../scene/material/material.zig").Material;
const ccoef = @import("../../../scene/material/collision_coefficients.zig");
const CC = ccoef.CC;
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
        tr: *Vec4f,
    ) bool {
        const d = ray.max_t;

        if (ro.offsetF(ray.min_t) >= d) {
            return true;
        }

        if (material.heterogeneousVolume()) {
            return tracking.transmittanceHetero(ray, material, prop, depth, sampler, worker, tr);
        }

        tr.* *= ccoef.attenuation3(cc.a + cc.s, d - ray.min_t);
        return true;
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
        const d = ray.max_t;

        if (!material.scatteringVolume()) {
            // Basically the "glass" case
            return Volume.initPass(ccoef.attenuation3(cc.a, d - ray.min_t));
        }

        if (math.allLess4(throughput, tracking.Abort_epsilon4)) {
            return Volume.initAbort();
        }

        if (material.volumetricTree()) |tree| {
            var local_ray = tracking.objectToTextureRay(ray, prop, worker);

            const srs = material.super().similarityRelationScale(depth);

            var result = Volume.initPass(@splat(1.0));

            if (material.emissive()) {
                while (local_ray.min_t < d) {
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

                    local_ray.setMinMaxT(ro.offsetF(local_ray.max_t), d);
                }
            } else {
                while (local_ray.min_t < d) {
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

                    local_ray.setMinMaxT(ro.offsetF(local_ray.max_t), d);
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
        const medium = vertex.mediums.top();
        const material = medium.material(worker.scene);

        if (material.denseSSSOptimization()) {
            return integrateHomogeneousSSS(medium.prop, material, vertex, frag, sampler, worker);
        }

        const ray_max_t = vertex.probe.ray.max_t;
        const limit = worker.scene.propAabbIntersectP(medium.prop, vertex.probe.ray) orelse ray_max_t;
        vertex.probe.ray.max_t = math.min(ro.offsetF(limit), ray_max_t);
        if (!worker.intersectAndResolveMask(&vertex.probe, frag, sampler)) {
            return false;
        }

        const tray = if (material.heterogeneousVolume())
            worker.scene.propTransformationAt(medium.prop, vertex.probe.time).worldToObjectRay(vertex.probe.ray)
        else
            vertex.probe.ray;

        const result = propScatter(
            tray,
            vertex.throughput,
            material,
            vertex.mediums.topCC(),
            medium.prop,
            vertex.probe.depth.volume,
            sampler,
            worker,
        );

        if (.Pass != result.event) {
            frag.prop = medium.prop;
            frag.part = medium.part;
            frag.p = vertex.probe.ray.point(result.t);
            frag.uvw = result.uvw;
        }

        frag.event = result.event;
        frag.vol_li = result.li;
        vertex.throughput *= result.tr;
        return true;
    }

    fn integrateSSS(prop: u32, material: *const Material, vertex: *Vertex, frag: *Fragment, sampler: *Sampler, worker: *Worker) bool {
        const cc = vertex.mediums.topCC();
        const g = material.super().volumetric_anisotropy;

        for (0..256) |_| {
            const hit = worker.propIntersect(prop, &vertex.probe, frag);
            if (!hit) {
                // We don't immediately abort even if not hitting the prop.
                // This way SSS looks less wrong in case of geometry that isn't "watertight".
                const limit = worker.scene.propAabbIntersectP(prop, vertex.probe.ray) orelse return false;
                vertex.probe.ray.setMaxT(limit);
            }

            const tray = if (material.heterogeneousVolume())
                worker.scene.propTransformationAt(prop, vertex.probe.time).worldToObjectRay(vertex.probe.ray)
            else
                vertex.probe.ray;

            const result = propScatter(
                tray,
                vertex.throughput,
                material,
                cc,
                prop,
                vertex.probe.depth.volume,
                sampler,
                worker,
            );

            vertex.throughput *= result.tr;

            if (hit and .Scatter != result.event) {
                worker.propInterpolateFragment(prop, &vertex.probe, frag);

                if (frag.sameHemisphere(vertex.probe.ray.direction)) {
                    vertex.mediums.pop();
                    frag.event = .ExitSSS;
                } else {
                    frag.event = .Pass;
                }

                frag.vol_li = @splat(0.0);

                return true;
            } else if (!hit and .Pass == result.event) {
                return false;
            }

            if (hlp.russianRoulette(&vertex.throughput, sampler.sample1D())) {
                return false;
            }

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

    fn integrateHomogeneousSSS(prop: u32, material: *const Material, vertex: *Vertex, frag: *Fragment, sampler: *Sampler, worker: *Worker) bool {
        const cc = vertex.mediums.topCC();
        const g = material.super().volumetric_anisotropy;

        const mu_t = cc.a + cc.s;
        const albedo = cc.s / mu_t;

        var local_weight: Vec4f = @splat(1.0);

        for (0..256) |_| {
            var channel_weights = local_weight * vertex.throughput;
            const sum_weights = channel_weights[0] + channel_weights[1] + channel_weights[2];

            if (sum_weights < 1e-6) {
                return false;
            }

            channel_weights /= @splat(sum_weights);

            const rc = sampler.sample1D();

            var channel_id: u32 = 2;
            if (rc < channel_weights[0]) {
                channel_id = 0;
            } else if (rc < channel_weights[0] + channel_weights[1]) {
                channel_id = 1;
            }

            const free_path = -@log(math.max(1.0 - sampler.sample1D(), 1e-10)) / mu_t[channel_id];

            // Calculate the visibility of the sample point for each channel
            const exp_free_path_sigma_t = @exp(@as(Vec4f, @splat(-free_path)) * mu_t);

            // Calculate the probability of generating a sample here
            var pdf = exp_free_path_sigma_t * mu_t;
            pdf /= @splat(math.dot3(pdf, channel_weights));

            local_weight *= pdf;

            if (hlp.russianRoulette(&local_weight, sampler.sample1D())) {
                return false;
            }

            vertex.probe.ray.max_t = free_path;

            if (!worker.propIntersect(prop, &vertex.probe, frag, true)) {
                const wil = sampleHg(g, sampler);
                const frame = Frame.init(vertex.probe.ray.direction);
                const wi = frame.frameToWorld(wil);

                vertex.probe.ray.origin = vertex.probe.ray.point(free_path);
                vertex.probe.ray.setDirection(wi, ro.Ray_max_t);

                local_weight *= albedo;
            } else {
                worker.propInterpolateFragment(prop, &vertex.probe, frag);

                if (frag.sameHemisphere(vertex.probe.ray.direction)) {
                    vertex.mediums.pop();
                    frag.event = .ExitSSS;
                } else {
                    frag.event = .Pass;
                }

                frag.vol_li = @splat(0.0);

                vertex.throughput *= local_weight;

                return true;
            }
        }

        return false;
    }

    fn sampleHg(g: f32, sampler: *Sampler) Vec4f {
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

        return math.smpl.sphereDirection(sin_theta, cos_theta, phi);
    }
};
