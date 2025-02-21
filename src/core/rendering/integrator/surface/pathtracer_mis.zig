const vt = @import("../../../scene/vertex.zig");
const Vertex = vt.Vertex;
const VertexPool = vt.Pool;
const Scene = @import("../../../scene/scene.zig").Scene;
const Light = @import("../../../scene/light/light.zig").Light;
const CausticsResolve = @import("../../../scene/renderstate.zig").CausticsResolve;
const MaterialSample = @import("../../../scene/material/material_sample.zig").Sample;
const bxdf = @import("../../../scene/material/bxdf.zig");
const Fragment = @import("../../../scene/shape/intersection.zig").Fragment;
const ro = @import("../../../scene/ray_offset.zig");
const Worker = @import("../../worker.zig").Worker;
const hlp = @import("../helper.zig");
const IValue = hlp.IValue;
const LightResult = hlp.LightResult;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const PathtracerMIS = struct {
    pub const Settings = struct {
        max_depth: hlp.Depth,
        light_sampling: hlp.LightSampling,
        regularize_roughness: bool,
        caustics_path: bool,
        caustics_resolve: CausticsResolve,
        photons_not_only_through_specular: bool,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: Self, input: Vertex, worker: *Worker) IValue {
        const max_depth = self.settings.max_depth;

        var result: IValue = .{};

        var vertices: VertexPool = undefined;
        vertices.start(input);

        while (vertices.iterate()) {
            while (vertices.consume()) |vertex| {
                const total_depth = vertex.probe.depth.total();

                var sampler = worker.pickSampler(total_depth);

                var frag: Fragment = undefined;
                _ = worker.nextEvent(vertex, &frag, sampler);
                if (.Abort == frag.event) {
                    continue;
                }

                const this_light = self.connectLight(vertex, &frag, sampler, worker);
                const split_weight: Vec4f = @splat(vertex.split_weight);
                var split_throughput = vertex.throughput * split_weight;

                vertex.shadow_catcher_occluded += split_throughput * this_light.occluded;
                vertex.shadow_catcher_unoccluded += split_throughput * this_light.unoccluded;

                const indirect_light_depth = total_depth - @as(u32, if (vertex.state.exit_sss) 1 else 0);
                result.add(split_throughput * this_light.emission, indirect_light_depth, 2, vertex.state.treat_as_singular);

                if (!frag.hit() or
                    vertex.probe.depth.surface >= max_depth.surface or
                    vertex.probe.depth.volume >= max_depth.volume or
                    .Absorb == frag.event)
                {
                    if (vertex.state.transparent) {
                        vertex.throughput *= @as(Vec4f, @splat(1.0)) - math.min4(this_light.emission, @splat(1.0));
                    }

                    continue;
                }

                if (hlp.russianRoulette(&vertex.throughput, sampler.sample1D())) {
                    continue;
                }

                const caustics = self.causticsResolve(vertex.state);
                const mat_sample = vertex.sample(&frag, sampler, caustics, worker);

                if (worker.aov.active()) {
                    worker.commonAOV(vertex, &frag, &mat_sample);
                }

                if (self.settings.regularize_roughness) {
                    vertex.min_alpha = math.max(vertex.min_alpha, mat_sample.super().averageAlpha());
                }

                split_throughput = vertex.throughput * split_weight;

                const gather_photons = vertex.state.started_specular or self.settings.photons_not_only_through_specular;
                if (mat_sample.canEvaluate() and vertex.state.primary_ray and gather_photons) {
                    result.direct += split_throughput * worker.photonLi(&frag, &mat_sample, sampler);
                }

                const max_splits = VertexPool.maxSplits(vertex, total_depth);

                const shadow_catcher = worker.scene.propIsShadowCatcher(frag.prop);

                const next_light = self.sampleLights(vertex, &frag, &mat_sample, max_splits, shadow_catcher, sampler, worker);

                if (shadow_catcher and 0 == vertex.probe.depth.surface) {
                    vertex.shadow_catcher_occluded = next_light.occluded;
                    vertex.shadow_catcher_unoccluded = next_light.unoccluded;
                    vertex.state.shadow_catcher_path = true;
                }

                const direct_light_depth = total_depth - @as(u32, if (.ExitSSS == frag.event) 1 else 0);
                result.add(split_throughput * next_light.emission, direct_light_depth, 1, false);

                vertex.state.exit_sss = .ExitSSS == frag.event;

                var bxdf_samples: bxdf.Samples = undefined;
                const sample_results = mat_sample.sample(sampler, max_splits, &bxdf_samples);
                const path_count: u32 = @intCast(sample_results.len);

                if (0 == path_count) {
                    vertex.throughput = @splat(0.0);
                }

                for (sample_results) |sample_result| {
                    var next_vertex = vertices.new();

                    next_vertex.* = vertex.*;
                    next_vertex.path_count = vertex.path_count * path_count;
                    next_vertex.split_weight = vertex.split_weight * sample_result.split_weight;

                    const class = sample_result.class;
                    if (class.specular) {
                        next_vertex.state.treat_as_singular = true;

                        if (vertex.state.primary_ray) {
                            next_vertex.state.started_specular = true;
                        }
                    } else if (!class.straight) {
                        next_vertex.state.treat_as_singular = false;
                        next_vertex.state.primary_ray = false;
                    }

                    if (!class.straight) {
                        next_vertex.state.is_translucent = mat_sample.isTranslucent();
                        next_vertex.depth = next_vertex.probe.depth;
                        next_vertex.bxdf_pdf = sample_result.pdf;
                        next_vertex.origin = frag.p;
                        next_vertex.geo_n = mat_sample.super().geometricNormal();
                    }

                    next_vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

                    next_vertex.probe.ray = frag.offsetRay(sample_result.wi, ro.RayMaxT);
                    next_vertex.probe.depth.increment(&frag);

                    if (0.0 == next_vertex.probe.wavelength) {
                        next_vertex.probe.wavelength = sample_result.wavelength;
                    }

                    if (class.transmission) {
                        next_vertex.interfaceChange(sample_result.wi, &frag, &mat_sample, worker.scene);
                    }

                    next_vertex.state.transparent = next_vertex.state.transparent and (class.transmission or class.straight);
                }

                sampler.incrementPadding();
            }
        }

        result.direct[3] = vertices.alpha;
        return result;
    }

    fn sampleLights(
        self: Self,
        vertex: *const Vertex,
        frag: *const Fragment,
        mat_sample: *const MaterialSample,
        max_material_splits: u32,
        shadow_catcher: bool,
        sampler: *Sampler,
        worker: *Worker,
    ) LightResult {
        var result = LightResult.empty();

        if (!mat_sample.canEvaluate()) {
            return result;
        }

        const p = frag.p;
        const n = mat_sample.super().geometricNormal();
        const translucent = mat_sample.isTranslucent();

        const select = sampler.sample1D();
        const split_threshold = self.settings.light_sampling.splitThreshold(vertex.probe.depth);

        var lights_buffer: Scene.Lights = undefined;
        const lights = worker.scene.randomLightSpatial(p, n, translucent, select, split_threshold, &lights_buffer);

        for (lights) |l| {
            result.addAssign(evaluateLight(
                l,
                vertex,
                frag,
                mat_sample,
                max_material_splits,
                shadow_catcher,
                split_threshold,
                sampler,
                worker,
            ));
        }

        return result;
    }

    fn evaluateLight(
        light_pick: Scene.LightPick,
        vertex: *const Vertex,
        frag: *const Fragment,
        mat_sample: *const MaterialSample,
        max_material_splits: u32,
        shadow_catcher: bool,
        light_split_threshold: f32,
        sampler: *Sampler,
        worker: *Worker,
    ) LightResult {
        const p = frag.p;
        const gn = mat_sample.super().geometricNormal();
        const translucent = mat_sample.isTranslucent();

        const light = worker.scene.light(light_pick.offset);

        const trafo = worker.scene.propTransformationAt(light.prop, vertex.probe.time);

        var unoccluded: Vec4f = @splat(0.0);
        var occluded: Vec4f = @splat(0.0);

        var samples_buffer: Scene.SamplesTo = undefined;
        const samples = light.sampleTo(p, gn, trafo, translucent, light_split_threshold, sampler, worker.scene, &samples_buffer);

        for (samples) |light_sample| {
            var shadow_probe = vertex.probe.clone(light.shadowRay(frag.offsetP(light_sample.wi), light_sample, worker.scene));

            var tr: Vec4f = @splat(1.0);
            if (!worker.visibility(&shadow_probe, sampler, &tr)) {
                if (!shadow_catcher) {
                    continue;
                } else {
                    tr = @splat(0.0);
                }
            }

            const radiance = light.evaluateTo(p, trafo, light_sample, sampler, worker.scene);

            const bxdf_result = mat_sample.evaluate(light_sample.wi, max_material_splits);

            const light_pdf = light_sample.pdf() * light_pick.pdf;
            const weight: Vec4f = @splat(hlp.predividedPowerHeuristic(light_pdf, bxdf_result.pdf));

            const unocc = weight * radiance * bxdf_result.reflection;

            unoccluded += unocc;
            occluded += tr * unocc;
        }

        if (shadow_catcher and light.shadowCatcherLight()) {
            return .{ .emission = @splat(0.0), .occluded = occluded, .unoccluded = unoccluded };
        }

        return .{ .emission = occluded, .occluded = @splat(0.0), .unoccluded = @splat(0.0) };
    }

    fn connectLight(self: Self, vertex: *Vertex, frag: *const Fragment, sampler: *Sampler, worker: *const Worker) LightResult {
        var result = LightResult.empty();

        if (!self.settings.caustics_path and vertex.state.treat_as_singular and !vertex.state.primary_ray) {
            return result;
        }

        const p = vertex.origin;
        const wo = -vertex.probe.ray.direction;

        const split_threshold = self.settings.light_sampling.splitThreshold(vertex.depth);

        const previous_shadow_catcher = 1 == vertex.probe.depth.surface and vertex.state.shadow_catcher_path;

        if (frag.hit()) {
            if (frag.evaluateRadiance(p, wo, sampler, worker.scene)) |local_energy| {
                const weight: Vec4f = @splat(worker.scene.lightPdf(vertex, frag, split_threshold));

                result.emission = weight * local_energy;
            }
        }

        var light_frag: Fragment = undefined;
        light_frag.event = .Pass;

        result.emission += worker.emission(vertex, &light_frag, split_threshold, sampler);

        const ray_max_t = vertex.probe.ray.max_t;
        if (previous_shadow_catcher) {
            vertex.probe.ray.max_t = ro.RayMaxT;
        }

        if (ro.RayMaxT == vertex.probe.ray.max_t) {
            for (worker.scene.infinite_props.items) |prop| {
                if (!worker.propIntersect(prop, &vertex.probe, &light_frag)) {
                    continue;
                }

                worker.propInterpolateFragment(prop, &vertex.probe, &light_frag);

                var local_energy = light_frag.evaluateRadiance(p, wo, sampler, worker.scene) orelse continue;

                const weight: Vec4f = @splat(worker.scene.lightPdf(vertex, &light_frag, split_threshold));

                local_energy *= weight;

                if (previous_shadow_catcher and worker.scene.propIsShadowCatcherLight(prop)) {
                    if (ro.RayMaxT == ray_max_t) {
                        // The light was not occluded
                        result.occluded += local_energy;
                        result.unoccluded += local_energy;
                    } else {
                        // The light was occluded, but we forced a hit
                        result.unoccluded += local_energy;
                    }
                } else {
                    result.emission += local_energy;
                }
            }

            vertex.probe.ray.max_t = ray_max_t;
        }

        return result;
    }

    fn causticsResolve(self: Self, state: Vertex.State) CausticsResolve {
        if (!state.primary_ray) {
            if (!self.settings.caustics_path) {
                return .Off;
            }

            return self.settings.caustics_resolve;
        }

        return .Full;
    }
};
