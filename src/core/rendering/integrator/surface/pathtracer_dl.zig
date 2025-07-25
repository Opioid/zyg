const Context = @import("../../../scene/context.zig").Context;
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
            worker.context.nextEvent(&vertex, &frag, sampler);
            if (.Abort == frag.event) {
                break;
            }

            const energy = self.connectLight(&vertex, &frag, sampler, worker.context);
            const weighted_energy = vertex.throughput * energy;

            const indirect_light_depth = total_depth - @as(u32, if (vertex.state.exit_sss) 1 else 0);
            result.add(weighted_energy, indirect_light_depth, 1, vertex.state.treat_as_singular);

            if (!frag.hit() or
                vertex.probe.depth.surface >= max_depth.surface or
                vertex.probe.depth.volume >= max_depth.volume or
                .Absorb == frag.event)
            {
                break;
            }

            if (hlp.russianRoulette(&vertex.throughput, sampler.sample1D())) {
                break;
            }

            const caustics = self.causticsResolve(vertex.state);
            const mat_sample = vertex.sample(&frag, sampler, caustics, worker.context);

            if (worker.aov.active()) {
                worker.commonAOV(&vertex, &frag, &mat_sample);
            }

            const lighting = self.directLight(&vertex, &frag, &mat_sample, sampler, worker.context);

            const direct_light_depth = total_depth - @as(u32, if (.ExitSSS == frag.event) 1 else 0);
            result.add(vertex.throughput * lighting, direct_light_depth, 1, false);

            vertex.state.exit_sss = .ExitSSS == frag.event;

            var bxdf_samples: bxdf.Samples = undefined;
            const sample_results = mat_sample.sample(sampler, 1, &bxdf_samples);
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

            vertex.probe.ray = frag.offsetRay(sample_result.wi, ro.RayMaxT);
            vertex.probe.depth.increment(&frag);

            if (0.0 == vertex.probe.wavelength) {
                vertex.probe.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                vertex.interfaceChange(sample_result.wi, &frag, &mat_sample, worker.context.scene);
            }

            vertex.state.transparent = vertex.state.transparent and (sample_result.class.transmission or sample_result.class.straight);

            sampler.incrementPadding();
        }

        result.direct[3] = hlp.composeAlpha(vertex.throughput, vertex.state.transparent);
        return result;
    }

    fn directLight(
        self: Self,
        vertex: *const Vertex,
        frag: *const Fragment,
        mat_sample: *const MaterialSample,
        sampler: *Sampler,
        context: Context,
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
        const lights = context.scene.randomLightSpatial(p, n, translucent, select, split_threshold, &lights_buffer);

        for (lights) |l| {
            const light = context.scene.light(l.offset);

            const trafo = context.scene.propTransformationAt(light.prop, vertex.probe.time);

            var samples_buffer: Scene.SamplesTo = undefined;
            const samples = light.sampleTo(p, n, trafo, vertex.probe.time, translucent, 0.0, sampler, context.scene, &samples_buffer);

            for (samples) |light_sample| {
                const shadow_probe = vertex.probe.clone(light.shadowRay(frag.offsetP(light_sample.wi), light_sample, context.scene));

                var tr: Vec4f = @splat(1.0);
                if (!context.visibility(shadow_probe, sampler, &tr)) {
                    continue;
                }

                const bxdf_result = mat_sample.evaluate(light_sample.wi, 1);

                const radiance = light.evaluateTo(p, trafo, light_sample, sampler, context);

                const weight = 1.0 / (l.pdf * light_sample.pdf());

                result += @as(Vec4f, @splat(weight)) * (tr * radiance * bxdf_result.reflection);
            }
        }

        return result;
    }

    fn connectLight(self: Self, vertex: *Vertex, frag: *const Fragment, sampler: *Sampler, context: Context) Vec4f {
        if (!self.settings.caustics_path and vertex.state.treat_as_singular and !vertex.state.primary_ray) {
            return @splat(0.0);
        }

        var energy: Vec4f = @splat(0.0);

        if (frag.hit()) {
            if (vertex.state.treat_as_singular or !Light.isLight(frag.lightId(context.scene))) {
                energy += vertex.evaluateRadiance(frag, sampler, context) orelse @splat(0.0);
            }
        }

        var light_frag: Fragment = undefined;
        light_frag.event = .Pass;

        if (vertex.state.treat_as_singular) {
            energy += context.emission(vertex, &light_frag, 0.0, sampler);
        }

        for (context.scene.infinite_props.items) |prop| {
            if (!context.propIntersect(prop, vertex.probe, sampler, &light_frag)) {
                continue;
            }

            if (vertex.state.treat_as_singular or !Light.isLight(light_frag.lightId(context.scene))) {
                context.propInterpolateFragment(prop, vertex.probe, &light_frag);

                energy += vertex.evaluateRadiance(&light_frag, sampler, context) orelse @splat(0.0);
            }
        }

        return energy;
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
