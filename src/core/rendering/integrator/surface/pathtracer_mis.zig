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
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const PathtracerMIS = struct {
    pub const Settings = struct {
        max_depth: hlp.Depth,
        light_sampling: hlp.LightSampling,
        caustics_path: bool,
        caustics_resolve: CausticsResolve,
        photons_not_only_through_specular: bool,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: Self, input: *const Vertex, worker: *Worker) IValue {
        const max_depth = self.settings.max_depth;

        var result: IValue = .{};

        var vertices: VertexPool = undefined;
        vertices.start(input);

        while (vertices.iterate()) {
            while (vertices.consume()) |vertex| {
                const total_depth = vertex.probe.depth.total();

                var sampler = worker.pickSampler(total_depth);

                var frag: Fragment = undefined;
                if (!worker.nextEvent(vertex, &frag, sampler)) {
                    continue;
                }

                const energy = self.connectLight(vertex, &frag, sampler, worker.scene);
                const split_weight: Vec4f = @splat(vertex.split_weight);
                const weighted_energy = vertex.throughput * split_weight * energy;

                if (vertex.state.treat_as_singular) {
                    result.emission += weighted_energy;
                } else {
                    result.reflection += weighted_energy;
                }

                if (vertex.probe.depth.surface >= max_depth.surface or vertex.probe.depth.volume >= max_depth.volume or .Absorb == frag.event) {
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

                const split_threshold = vertex.throughput * split_weight;

                const gather_photons = vertex.state.started_specular or self.settings.photons_not_only_through_specular;
                if (mat_sample.canEvaluate() and vertex.state.primary_ray and gather_photons) {
                    result.reflection += split_threshold * worker.photonLi(&frag, &mat_sample, sampler);
                }

                const split = vertex.path_count <= 2 and (vertex.state.primary_ray or total_depth < 1);

                result.reflection += split_threshold * self.sampleLights(vertex, &frag, &mat_sample, split, sampler, worker);

                var bxdf_samples: bxdf.Samples = undefined;
                const sample_results = mat_sample.sample(sampler, split, &bxdf_samples);
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

                    next_vertex.probe.ray.origin = frag.offsetP(sample_result.wi);
                    next_vertex.probe.ray.setDirection(sample_result.wi, ro.Ray_max_t);
                    next_vertex.probe.depth.increment(&frag);

                    if (0.0 == next_vertex.probe.wavelength) {
                        next_vertex.probe.wavelength = sample_result.wavelength;
                    }

                    if (class.transmission) {
                        next_vertex.interfaceChange(&frag, sample_result.wi, sampler, worker.scene);
                    }

                    next_vertex.state.transparent = next_vertex.state.transparent and (class.transmission or class.straight);
                }

                sampler.incrementPadding();
            }
        }

        result.reflection[3] = vertices.alpha;
        return result;
    }

    fn sampleLights(
        self: Self,
        vertex: *const Vertex,
        frag: *const Fragment,
        mat_sample: *const MaterialSample,
        material_split: bool,
        sampler: *Sampler,
        worker: *Worker,
    ) Vec4f {
        var result: Vec4f = @splat(0.0);

        const p = frag.p;
        const n = mat_sample.super().geometricNormal();
        const translucent = mat_sample.isTranslucent();

        const select = sampler.sample1D();
        const split_threshold = self.settings.light_sampling.splitThreshold(vertex.probe.depth);

        var lights_buffer: Scene.Lights = undefined;
        const lights = worker.scene.randomLightSpatial(p, n, translucent, select, split_threshold, &lights_buffer);

        for (lights) |l| {
            const light = worker.scene.light(l.offset);

            result += evaluateLight(light, l.pdf, vertex, frag, mat_sample, material_split, sampler, worker);
        }

        return result;
    }

    fn evaluateLight(
        light: Light,
        light_weight: f32,
        vertex: *const Vertex,
        frag: *const Fragment,
        mat_sample: *const MaterialSample,
        split: bool,
        sampler: *Sampler,
        worker: *Worker,
    ) Vec4f {
        const p = frag.p;

        const light_sample = light.sampleTo(
            p,
            mat_sample.super().geometricNormal(),
            vertex.probe.time,
            mat_sample.isTranslucent(),
            sampler,
            worker.scene,
        ) orelse return @splat(0.0);

        var shadow_probe = vertex.probe.clone(light.shadowRay(frag.offsetP(light_sample.wi), light_sample, worker.scene));

        const tr = worker.visibility(&shadow_probe, sampler) orelse return @splat(0.0);

        const radiance = light.evaluateTo(p, light_sample, sampler, worker.scene);

        const bxdf_result = mat_sample.evaluate(light_sample.wi, split);

        const light_pdf = light_sample.pdf() * light_weight;
        const weight: Vec4f = @splat(hlp.predividedPowerHeuristic(light_pdf, bxdf_result.pdf()));

        return weight * (tr * radiance * bxdf_result.reflection);
    }

    fn connectLight(
        self: Self,
        vertex: *const Vertex,
        frag: *const Fragment,
        sampler: *Sampler,
        scene: *const Scene,
    ) Vec4f {
        if (!self.settings.caustics_path and vertex.state.treat_as_singular and !vertex.state.primary_ray) {
            return @splat(0.0);
        }

        const p = vertex.origin;
        const wo = -vertex.probe.ray.direction;
        const energy = frag.evaluateRadiance(p, wo, sampler, scene) orelse return @splat(0.0);

        const light_id = frag.lightId(scene);
        if (vertex.state.treat_as_singular or !Light.isLight(light_id)) {
            return energy;
        }

        const translucent = vertex.state.is_translucent;
        const split_threshold = self.settings.light_sampling.splitThreshold(vertex.depth);

        const select_pdf = scene.lightPdfSpatial(light_id, p, vertex.geo_n, translucent, split_threshold);
        const light = scene.light(light_id);
        const sample_pdf = light.pdf(vertex, frag, scene);
        const weight: Vec4f = @splat(hlp.powerHeuristic(vertex.bxdf_pdf, sample_pdf * select_pdf));

        return weight * energy;
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
