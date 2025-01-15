const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Scene = @import("../../../scene/scene.zig").Scene;
const Worker = @import("../../worker.zig").Worker;
const Light = @import("../../../scene/light/light.zig").Light;
const CausticsResolve = @import("../../../scene/renderstate.zig").CausticsResolve;
const hlp = @import("../helper.zig");
const IValue = hlp.IValue;
const MaterialSample = @import("../../../scene/material/material_sample.zig").Sample;
const bxdf = @import("../../../scene/material/bxdf.zig");
const ro = @import("../../../scene/ray_offset.zig");
const Fragment = @import("../../../scene/shape/intersection.zig").Fragment;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const PathtracerDL = struct {
    pub const Settings = struct {
        max_depth: hlp.Depth,
        light_sampling: hlp.LightSampling,
        caustics_path: bool,
        caustics_resolve: CausticsResolve,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: Self, input: Vertex, worker: *Worker) IValue {
        const max_depth = self.settings.max_depth;

        var vertex = input;

        var result: IValue = .{};

        while (true) {
            const total_depth = vertex.probe.depth.total();

            var sampler = worker.pickSampler(total_depth);

            var frag: Fragment = undefined;
            if (!worker.nextEvent(&vertex, &frag, sampler)) {
                break;
            }

            if (vertex.state.treat_as_singular or !Light.isLight(frag.lightId(worker.scene))) {
                const energy = self.connectLight(&vertex, &frag, sampler, worker.scene);
                const weighted_energy = vertex.throughput * energy;

                if (vertex.state.treat_as_singular) {
                    result.emission += weighted_energy;
                } else {
                    result.reflection += weighted_energy;
                }
            }

            if (vertex.probe.depth.surface >= max_depth.surface or vertex.probe.depth.volume >= max_depth.volume or .Absorb == frag.event) {
                break;
            }

            if (hlp.russianRoulette(&vertex.throughput, sampler.sample1D())) {
                break;
            }

            const caustics = self.causticsResolve(vertex.state);
            const mat_sample = vertex.sample(&frag, sampler, caustics, worker);

            if (worker.aov.active()) {
                worker.commonAOV(&vertex, &frag, &mat_sample);
            }

            result.reflection += vertex.throughput * self.directLight(&vertex, &frag, &mat_sample, sampler, worker);

            var bxdf_samples: bxdf.Samples = undefined;
            const sample_results = mat_sample.sample(sampler, false, &bxdf_samples);
            if (0 == sample_results.len) {
                vertex.throughput = @splat(0.0);
                break;
            }

            const sample_result = sample_results[0];

            if (sample_result.class.specular) {
                vertex.state.treat_as_singular = true;
            } else if (!sample_result.class.straight) {
                vertex.state.treat_as_singular = false;
                vertex.state.primary_ray = false;
            }

            if (!sample_result.class.straight) {
                vertex.origin = frag.p;
            }

            vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

            vertex.probe.ray.origin = frag.offsetP(sample_result.wi);
            vertex.probe.ray.setDirection(sample_result.wi, ro.Ray_max_t);
            vertex.probe.depth.increment(&frag);

            if (0.0 == vertex.probe.wavelength) {
                vertex.probe.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                vertex.interfaceChange(&frag, sample_result.wi, sampler, worker.scene);
            }

            vertex.state.transparent = vertex.state.transparent and (sample_result.class.transmission or sample_result.class.straight);

            sampler.incrementPadding();
        }

        result.reflection[3] = hlp.composeAlpha(vertex.throughput, vertex.state.transparent);
        return result;
    }

    fn directLight(
        self: Self,
        vertex: *const Vertex,
        frag: *const Fragment,
        mat_sample: *const MaterialSample,
        sampler: *Sampler,
        worker: *Worker,
    ) Vec4f {
        var result: Vec4f = @splat(0.0);

        if (!mat_sample.canEvaluate()) {
            return result;
        }

        const n = mat_sample.super().geometricNormal();
        const p = frag.p;

        const translucent = mat_sample.isTranslucent();

        const select = sampler.sample1D();
        const split_threshold = self.settings.light_sampling.splitThreshold(vertex.probe.depth);

        var lights_buffer: Scene.Lights = undefined;
        const lights = worker.scene.randomLightSpatial(p, n, translucent, select, split_threshold, &lights_buffer);

        for (lights) |l| {
            const light = worker.scene.light(l.offset);

            const trafo = worker.scene.propTransformationAt(light.prop, vertex.probe.time);

            var samples_buffer: Scene.SamplesTo = undefined;
            const samples = light.sampleTo(p, n, trafo, translucent, 0.0, sampler, worker.scene, &samples_buffer);

            for (samples) |light_sample| {
                var shadow_probe = vertex.probe.clone(light.shadowRay(frag.offsetP(light_sample.wi), light_sample, worker.scene));

                var tr: Vec4f = @splat(1.0);
                if (!worker.visibility(&shadow_probe, sampler, &tr)) {
                    continue;
                }

                const bxdf_result = mat_sample.evaluate(light_sample.wi, false);

                const radiance = light.evaluateTo(p, trafo, light_sample, sampler, worker.scene);

                const weight = 1.0 / (l.pdf * light_sample.pdf());

                result += @as(Vec4f, @splat(weight)) * (tr * radiance * bxdf_result.reflection);
            }
        }

        return result;
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
        return frag.evaluateRadiance(p, wo, sampler, scene) orelse @splat(0.0);
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
