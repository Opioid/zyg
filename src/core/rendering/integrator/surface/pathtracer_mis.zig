const Ray = @import("../../../scene/ray.zig").Ray;
const Scene = @import("../../../scene/scene.zig").Scene;
const vrt = @import("../../../scene/vertex.zig");
const Vertex = vrt.Vertex;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const Filter = @import("../../../image/texture/texture_sampler.zig").Filter;
const Light = @import("../../../scene/light/light.zig").Light;
const Max_lights = @import("../../../scene/light/light_tree.zig").Tree.Max_lights;
const hlp = @import("../helper.zig");
const BxdfSample = @import("../../../scene/material/bxdf.zig").Sample;
const MaterialSample = @import("../../../scene/material/sample.zig").Sample;
const ro = @import("../../../scene/ray_offset.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PathtracerMIS = struct {
    const Num_dedicated_samplers = 3;

    pub const Settings = struct {
        num_samples: u32,
        min_bounces: u32,
        max_bounces: u32,

        light_sampling: hlp.LightSampling,

        avoid_caustics: bool,
        photons_not_only_through_specular: bool,
    };

    settings: Settings,

    samplers: [2]Sampler,

    const Self = @This();

    pub fn startPixel(self: *Self, sample: u32, seed: u32) void {
        const os = sample *% self.settings.num_samples;
        for (self.samplers) |*s| {
            s.startPixel(os, seed);
        }
    }

    pub fn li(
        self: *Self,
        ray: *Ray,
        isec: *Intersection,
        gather_photons: bool,
        worker: *Worker,
        initial_stack: *const InterfaceStack,
    ) Vec4f {
        const num_samples = self.settings.num_samples;
        const num_samples_reciprocal = 1.0 / @intToFloat(f32, num_samples);

        var result = @splat(4, @as(f32, 0.0));

        var i = num_samples;
        while (i > 0) : (i -= 1) {
            worker.resetInterfaceStack(initial_stack);

            var split_ray = ray.*;
            var split_isec = isec.*;

            result += @splat(4, num_samples_reciprocal) * self.integrate(
                &split_ray,
                &split_isec,
                num_samples == i and gather_photons,
                worker,
            );

            for (self.samplers) |*s| {
                s.incrementSample();
            }
        }

        return result;
    }

    fn integrate(self: *Self, ray: *Ray, isec: *Intersection, gather_photons: bool, worker: *Worker) Vec4f {
        const max_bounces = self.settings.max_bounces;

        var sample_result = BxdfSample{};

        var throughput = @splat(4, @as(f32, 1.0));
        var result = @splat(4, @as(f32, 0.0));

        {
            var pure_emissive: bool = undefined;
            const energy = isec.evaluateRadiance(
                ray.ray.origin,
                -ray.ray.direction,
                null,
                worker.scene,
                &pure_emissive,
            ) orelse @splat(4, @as(f32, 0.0));

            if (pure_emissive) {
                return hlp.composeAlpha(energy, throughput, false);
            }

            result += energy;
        }

        worker.vertices.start(.{ .ray = ray.*, .isec = isec.* });

        while (!worker.vertices.empty()) {
            for (worker.vertices.consume()) |v| {
                var vertex = v;

                const wo = -vertex.ray.ray.direction;
                const pr = vertex.state.primary_ray;

                const filter: ?Filter = if (vertex.ray.depth <= 1 or pr) null else .Nearest;
                const avoid_caustics = self.settings.avoid_caustics and !pr;
                const straight_border = vertex.state.from_subsurface;

                const mat_sample = worker.sampleMaterial(
                    vertex.ray,
                    wo,
                    vertex.wo1,
                    vertex.isec,
                    filter,
                    0.0,
                    avoid_caustics,
                    straight_border,
                );

                if (worker.aov.active()) {
                    worker.commonAOV(throughput, vertex.ray, vertex.isec, &mat_sample, pr);
                }

                vertex.wo1 = wo;

                var sampler = self.pickSampler(vertex.ray.depth);

                result += throughput * self.sampleLights(vertex, &mat_sample, filter, sampler, worker);

                var effective_bxdf_pdf = sample_result.pdf;

                sample_result = mat_sample.sample(sampler);
                if (0.0 == sample_result.pdf) {
                    continue;
                }

                if (sample_result.class.specular) {
                    if (avoid_caustics) {
                        continue;
                    }

                    vertex.state.treat_as_singular = true;
                } else if (!sample_result.class.straight) {
                    vertex.state.treat_as_singular = false;

                    effective_bxdf_pdf = sample_result.pdf;

                    if (pr) {
                        vertex.state.primary_ray = false;

                        const indirect = !vertex.state.direct and 0 != vertex.ray.depth;
                        if (gather_photons and (self.settings.photons_not_only_through_specular or indirect)) {
                            worker.addPhoton(throughput * worker.photonLi(vertex.isec, &mat_sample));
                        }
                    }
                }

                if (!(sample_result.class.straight and sample_result.class.transmission)) {
                    vertex.ray.depth += 1;
                }

                if (sample_result.class.straight) {
                    vertex.ray.ray.setMinMaxT(ro.offsetF(vertex.ray.ray.maxT()), ro.Ray_max_t);
                } else {
                    vertex.ray.ray.origin = vertex.isec.offsetP(sample_result.wi);
                    vertex.ray.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                    vertex.state.direct = false;
                    vertex.state.from_subsurface = false;
                }

                if (0.0 == vertex.ray.wavelength) {
                    vertex.ray.wavelength = sample_result.wavelength;
                }

                throughput *= sample_result.reflection / @splat(4, sample_result.pdf);

                if (sample_result.class.transmission) {
                    worker.interfaceChange(sample_result.wi, vertex.isec);
                }

                vertex.state.from_subsurface = vertex.state.from_subsurface or vertex.isec.subsurface;

                if (sample_result.class.straight and !vertex.state.treat_as_singular) {
                    sample_result.pdf = effective_bxdf_pdf;
                } else {
                    vertex.state.is_translucent = mat_sample.isTranslucent();
                    vertex.geo_n = mat_sample.super().geometricNormal();
                }

                if (!worker.interface_stack.empty()) {
                    const vr = worker.volume(&vertex.ray, &vertex.isec, filter, sampler);

                    if (.Absorb == vr.event) {
                        if (0 == vertex.ray.depth) {
                            // This is the direct eye-light connection for the volume case.
                            result += vr.li;
                        } else {
                            const w = self.connectVolumeLight(
                                vertex,
                                effective_bxdf_pdf,
                                worker.scene,
                            );

                            result += @splat(4, w) * (throughput * vr.li);
                        }

                        continue;
                    }

                    // This is only needed for Tracking_single at the moment...
                    result += throughput * vr.li;
                    throughput *= vr.tr;

                    if (.Abort == vr.event) {
                        continue;
                    }

                    if (.Scatter == vr.event and vertex.ray.depth >= max_bounces) {
                        continue;
                    }
                } else if (!worker.intersectAndResolveMask(&vertex.ray, filter, &vertex.isec)) {
                    continue;
                }

                var pure_emissive: bool = undefined;
                const radiance = self.connectLight(
                    vertex,
                    sample_result,
                    filter,
                    worker.scene,
                    &pure_emissive,
                );

                result += throughput * radiance;

                if (pure_emissive) {
                    vertex.state.direct = vertex.state.direct and (!vertex.isec.visibleInCamera(worker.scene) and vertex.ray.ray.maxT() >= ro.Ray_max_t);
                    continue;
                }

                if (vertex.ray.depth >= self.settings.max_bounces) {
                    continue;
                }

                if (vertex.ray.depth >= self.settings.min_bounces) {
                    if (hlp.russianRoulette(&throughput, sampler.sample1D())) {
                        continue;
                    }
                }

                worker.vertices.push(vertex);

                sampler.incrementPadding();
            }

            worker.vertices.cycle();
        }

        //  return hlp.composeAlpha(result, throughput, vertex.state.direct);

        return hlp.composeAlpha(result, throughput, true);
    }

    fn sampleLights(
        self: *const Self,
        vertex: Vertex,
        mat_sample: *const MaterialSample,
        filter: ?Filter,
        sampler: *Sampler,
        worker: *Worker,
    ) Vec4f {
        var result = @splat(4, @as(f32, 0.0));

        if (!mat_sample.canEvaluate()) {
            return result;
        }

        const translucent = mat_sample.isTranslucent();

        const n = mat_sample.super().geometricNormal();
        const p = vertex.isec.offsetPN(n, translucent);

        const select = sampler.sample1D();
        const split = self.splitting(vertex.ray.depth);

        const lights = worker.randomLightSpatial(p, n, translucent, select, split);

        for (lights) |l| {
            const light = worker.scene.light(l.offset);

            result += evaluateLight(light, l.pdf, vertex.ray, p, vertex.isec, mat_sample, filter, sampler, worker);
        }

        return result;
    }

    fn evaluateLight(
        light: Light,
        light_weight: f32,
        history: Ray,
        p: Vec4f,
        isec: Intersection,
        mat_sample: *const MaterialSample,
        filter: ?Filter,
        sampler: *Sampler,
        worker: *Worker,
    ) Vec4f {
        // Light source importance sample
        const light_sample = light.sampleTo(
            p,
            mat_sample.super().geometricNormal(),
            history.time,
            mat_sample.isTranslucent(),
            sampler,
            worker.scene,
        ) orelse return @splat(4, @as(f32, 0.0));

        var shadow_ray = Ray.init(
            p,
            light_sample.wi,
            p[3],
            light_sample.offset(),
            history.depth,
            history.wavelength,
            history.time,
        );

        const tr = worker.transmitted(
            &shadow_ray,
            mat_sample.super().wo,
            isec,
            filter,
        ) orelse return @splat(4, @as(f32, 0.0));

        const bxdf = mat_sample.evaluate(light_sample.wi);

        const radiance = light.evaluateTo(p, light_sample, filter, worker.scene);

        const light_pdf = light_sample.pdf() * light_weight;
        const weight = hlp.predividedPowerHeuristic(light_pdf, bxdf.pdf());

        return @splat(4, weight) * (tr * radiance * bxdf.reflection);
    }

    fn connectLight(
        self: *const Self,
        vertex: Vertex,
        sample_result: BxdfSample,
        filter: ?Filter,
        scene: *const Scene,
        pure_emissive: *bool,
    ) Vec4f {
        const wo = -sample_result.wi;
        const energy = vertex.isec.evaluateRadiance(
            vertex.ray.ray.origin,
            wo,
            filter,
            scene,
            pure_emissive,
        ) orelse return @splat(4, @as(f32, 0.0));

        const light_id = vertex.isec.lightId(scene);
        if (vertex.state.treat_as_singular or !Light.isAreaLight(light_id)) {
            return energy;
        }

        const translucent = vertex.state.is_translucent;
        const split = self.splitting(vertex.ray.depth);

        const light_pick = scene.lightPdfSpatial(light_id, vertex.ray.ray.origin, vertex.geo_n, translucent, split);
        const light = scene.light(light_pick.offset);

        const pdf = light.pdf(vertex.ray, vertex.geo_n, vertex.isec, translucent, scene);
        const weight = hlp.powerHeuristic(sample_result.pdf, pdf * light_pick.pdf);

        return @splat(4, weight) * energy;
    }

    fn connectVolumeLight(
        self: *const Self,
        vertex: Vertex,
        bxdf_pdf: f32,
        scene: *const Scene,
    ) f32 {
        const light_id = vertex.isec.lightId(scene);

        if (vertex.state.treat_as_singular or !Light.isLight(light_id)) {
            return 1.0;
        }

        const translucent = vertex.state.is_translucent;
        const split = self.splitting(vertex.ray.depth);

        const light_pick = scene.lightPdfSpatial(light_id, vertex.ray.ray.origin, vertex.geo_n, translucent, split);
        const light = scene.light(light_pick.offset);

        const pdf = light.pdf(vertex.ray, vertex.geo_n, vertex.isec, translucent, scene);

        return hlp.powerHeuristic(bxdf_pdf, pdf * light_pick.pdf);
    }

    fn splitting(self: *const Self, bounce: u32) bool {
        return .Adaptive == self.settings.light_sampling and bounce < Num_dedicated_samplers;
    }

    fn pickSampler(self: *Self, bounce: u32) *Sampler {
        if (bounce < 4) {
            return &self.samplers[0];
        }

        return &self.samplers[1];
    }
};

pub const Factory = struct {
    settings: PathtracerMIS.Settings,

    pub fn create(self: Factory, rng: *RNG) PathtracerMIS {
        return .{
            .settings = self.settings,
            .samplers = .{ .{ .Sobol = .{} }, .{ .Random = .{ .rng = rng } } },
        };
    }
};
