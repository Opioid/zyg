const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Scene = @import("../../../scene/scene.zig").Scene;
const Worker = @import("../../worker.zig").Worker;
const Light = @import("../../../scene/light/light.zig").Light;
const CausticsResolve = @import("../../../scene/renderstate.zig").CausticsResolve;
const hlp = @import("../helper.zig");
const MaterialSample = @import("../../../scene/material/sample.zig").Sample;
const bxdf = @import("../../../scene/material/bxdf.zig");
const ro = @import("../../../scene/ray_offset.zig");
const Intersection = @import("../../../scene/shape/intersection.zig").Intersection;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PathtracerDL = struct {
    pub const Settings = struct {
        min_bounces: u32,
        max_bounces: u32,

        light_sampling: hlp.LightSampling,
        caustics_path: bool,
        caustics_resolve: CausticsResolve,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: *const Self, input: Vertex, worker: *Worker) Vec4f {
        var vertex = input;
        var result: Vec4f = @splat(0.0);

        while (true) {
            var sampler = worker.pickSampler(vertex.probe.depth);

            var isec: Intersection = undefined;
            if (!worker.nextEvent(false, &vertex, &isec, sampler)) {
                break;
            }

            if (vertex.state.treat_as_singular or !Light.isLight(isec.lightId(worker.scene))) {
                const energy = self.connectLight(&vertex, &isec, sampler, worker.scene);
                result += vertex.throughput * energy;
            }

            if (vertex.probe.depth >= self.settings.max_bounces or .Absorb == isec.event) {
                break;
            }

            if (vertex.probe.depth >= self.settings.min_bounces) {
                const rr = hlp.russianRoulette(vertex.throughput, vertex.throughput_old, sampler.sample1D()) orelse break;
                vertex.throughput /= @splat(rr);
            }

            const caustics = self.causticsResolve(vertex.state);
            const mat_sample = vertex.sample(&isec, sampler, caustics, worker);

            if (worker.aov.active()) {
                worker.commonAOV(&vertex, &isec, &mat_sample);
            }

            result += vertex.throughput * self.directLight(&vertex, &isec, &mat_sample, sampler, worker);

            var bxdf_samples: bxdf.Samples = undefined;
            const sample_results = mat_sample.sample(sampler, false, &bxdf_samples);
            if (0 == sample_results.len) {
                break;
            }

            const sample_result = sample_results[0];

            if (sample_result.class.specular) {
                vertex.state.treat_as_singular = true;
            } else if (!sample_result.class.straight) {
                vertex.state.treat_as_singular = false;
                vertex.state.primary_ray = false;
            }

            vertex.throughput_old = vertex.throughput;
            vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

            vertex.probe.ray.origin = isec.offsetP(sample_result.wi);
            vertex.probe.ray.setDirection(sample_result.wi, ro.Ray_max_t);
            vertex.probe.depth += 1;

            if (!sample_result.class.straight) {
                vertex.state.from_subsurface = isec.subsurface();
                vertex.origin = isec.p;
            }

            if (0.0 == vertex.probe.wavelength) {
                vertex.probe.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                vertex.interfaceChange(&isec, sample_result.wi, sampler, worker.scene);
            }

            vertex.state.transparent = vertex.state.transparent and (sample_result.class.transmission or sample_result.class.straight);

            sampler.incrementPadding();
        }

        return hlp.composeAlpha(result, vertex.throughput, vertex.state.transparent);
    }

    fn directLight(
        self: *const Self,
        vertex: *const Vertex,
        isec: *const Intersection,
        mat_sample: *const MaterialSample,
        sampler: *Sampler,
        worker: *Worker,
    ) Vec4f {
        var result: Vec4f = @splat(0.0);

        if (!mat_sample.canEvaluate()) {
            return result;
        }

        const n = mat_sample.super().geometricNormal();
        const p = isec.p;

        const translucent = mat_sample.isTranslucent();

        const select = sampler.sample1D();
        const split = self.splitting(vertex.probe.depth);

        var lights_buffer: Scene.Lights = undefined;
        const lights = worker.scene.randomLightSpatial(p, n, translucent, select, split, &lights_buffer);

        for (lights) |l| {
            const light = worker.scene.light(l.offset);
            const light_sample = light.sampleTo(
                p,
                n,
                vertex.probe.time,
                translucent,
                sampler,
                worker.scene,
            ) orelse continue;

            var shadow_probe = vertex.probe.clone(light.shadowRay(isec.offsetP(light_sample.wi), light_sample, worker.scene));

            const tr = worker.visibility(&shadow_probe, isec, &vertex.interfaces, sampler) orelse continue;

            const bxdf_result = mat_sample.evaluate(light_sample.wi, false);

            const radiance = light.evaluateTo(p, light_sample, sampler, worker.scene);

            const weight = 1.0 / (l.pdf * light_sample.pdf());

            result += @as(Vec4f, @splat(weight)) * (tr * radiance * bxdf_result.reflection);
        }

        return result;
    }

    fn connectLight(
        self: *const Self,
        vertex: *const Vertex,
        isec: *const Intersection,
        sampler: *Sampler,
        scene: *const Scene,
    ) Vec4f {
        if (!self.settings.caustics_path and vertex.state.treat_as_singular and !vertex.state.primary_ray) {
            return @splat(0.0);
        }

        const p = vertex.probe.ray.origin;
        const wo = -vertex.probe.ray.direction;
        return isec.evaluateRadiance(p, wo, sampler, scene) orelse @splat(0.0);
    }

    fn splitting(self: *const Self, bounce: u32) bool {
        return .Adaptive == self.settings.light_sampling and bounce < 3;
    }

    fn causticsResolve(self: *const Self, state: Vertex.State) CausticsResolve {
        if (!state.primary_ray) {
            if (!self.settings.caustics_path) {
                return .Off;
            }

            return self.settings.caustics_resolve;
        }

        return .Full;
    }
};

pub const Factory = struct {
    settings: PathtracerDL.Settings,

    pub fn create(self: Factory) PathtracerDL {
        return .{ .settings = self.settings };
    }
};
