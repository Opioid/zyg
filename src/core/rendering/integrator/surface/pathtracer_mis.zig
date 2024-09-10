const vt = @import("../../../scene/vertex.zig");
const Vertex = vt.Vertex;
const VertexPool = vt.Pool;
const Scene = @import("../../../scene/scene.zig").Scene;
const Light = @import("../../../scene/light/light.zig").Light;
const CausticsResolve = @import("../../../scene/renderstate.zig").CausticsResolve;
const MaterialSample = @import("../../../scene/material/material_sample.zig").Sample;
const bxdf = @import("../../../scene/material/bxdf.zig");
const Intersection = @import("../../../scene/shape/intersection.zig").Intersection;
const ro = @import("../../../scene/ray_offset.zig");
const Worker = @import("../../worker.zig").Worker;
const hlp = @import("../helper.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const PathtracerMIS = struct {
    pub const Settings = struct {
        min_bounces: u32,
        max_bounces: u32,

        light_sampling: hlp.LightSampling,
        caustics_path: bool,
        caustics_resolve: CausticsResolve,
        photons_not_only_through_specular: bool,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: *const Self, input: *const Vertex, worker: *Worker) Vec4f {
        const max_bounces = self.settings.max_bounces;

        var result: Vec4f = @splat(0.0);

        var vertices: VertexPool = .{};
        vertices.start(input);

        while (vertices.iterate()) {
            while (vertices.consume()) |vertex| {
                var sampler = worker.pickSampler(vertex.probe.depth);

                var isec: Intersection = undefined;
                if (!worker.nextEvent(false, vertex, &isec, sampler)) {
                    continue;
                }

                const energy = self.connectLight(vertex, &isec, sampler, worker.scene);
                const split_weight: Vec4f = @splat(vertex.split_weight);
                result += vertex.throughput * split_weight * energy;

                if (vertex.probe.depth >= max_bounces or .Absorb == isec.event) {
                    continue;
                }

                if (vertex.probe.depth >= self.settings.min_bounces) {
                    const rr = hlp.russianRoulette(vertex.throughput, vertex.throughput_old, sampler.sample1D()) orelse continue;
                    vertex.throughput /= @splat(rr);
                }

                const caustics = self.causticsResolve(vertex.state);
                const mat_sample = vertex.sample(&isec, sampler, caustics, worker);

                if (worker.aov.active()) {
                    worker.commonAOV(vertex, &isec, &mat_sample);
                }

                const gather_photons = vertex.state.started_specular or self.settings.photons_not_only_through_specular;
                if (mat_sample.canEvaluate() and vertex.state.primary_ray and gather_photons) {
                    worker.addPhoton(vertex.throughput * split_weight * worker.photonLi(&isec, &mat_sample, sampler));
                }

                const split = vertex.path_count <= 2 and vertex.state.primary_ray;

                result += vertex.throughput * split_weight * self.sampleLights(vertex, &isec, &mat_sample, split, sampler, worker);

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

                    next_vertex.throughput_old = next_vertex.throughput;
                    next_vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

                    next_vertex.probe.ray.origin = isec.offsetP(sample_result.wi);
                    next_vertex.probe.ray.setDirection(sample_result.wi, ro.Ray_max_t);
                    next_vertex.probe.depth += 1;

                    if (!class.straight) {
                        next_vertex.state.from_subsurface = isec.subsurface();
                        next_vertex.state.is_translucent = mat_sample.isTranslucent();
                        next_vertex.bxdf_pdf = sample_result.pdf;
                        next_vertex.origin = isec.p;
                        next_vertex.geo_n = mat_sample.super().geometricNormal();
                    }

                    if (0.0 == next_vertex.probe.wavelength) {
                        next_vertex.probe.wavelength = sample_result.wavelength;
                    }

                    if (class.transmission) {
                        next_vertex.interfaceChange(&isec, sample_result.wi, sampler, worker.scene);
                    }

                    next_vertex.state.transparent = next_vertex.state.transparent and (class.transmission or class.straight);
                }

                sampler.incrementPadding();
            }
        }

        return .{ result[0], result[1], result[2], vertices.alpha };
    }

    fn sampleLights(
        self: *const Self,
        vertex: *const Vertex,
        isec: *const Intersection,
        mat_sample: *const MaterialSample,
        material_split: bool,
        sampler: *Sampler,
        worker: *Worker,
    ) Vec4f {
        var result: Vec4f = @splat(0.0);

        const p = isec.p;
        const n = mat_sample.super().geometricNormal();
        const translucent = mat_sample.isTranslucent();

        const select = sampler.sample1D();
        const split = self.splitting(vertex.probe.depth);

        var lights_buffer: Scene.Lights = undefined;
        const lights = worker.scene.randomLightSpatial(p, n, translucent, select, split, &lights_buffer);

        for (lights) |l| {
            const light = worker.scene.light(l.offset);

            result += evaluateLight(light, l.pdf, vertex, isec, mat_sample, material_split, sampler, worker);
        }

        return result;
    }

    fn evaluateLight(
        light: Light,
        light_weight: f32,
        vertex: *const Vertex,
        isec: *const Intersection,
        mat_sample: *const MaterialSample,
        split: bool,
        sampler: *Sampler,
        worker: *Worker,
    ) Vec4f {
        const p = isec.p;

        const light_sample = light.sampleTo(
            p,
            mat_sample.super().geometricNormal(),
            vertex.probe.time,
            mat_sample.isTranslucent(),
            sampler,
            worker.scene,
        ) orelse return @splat(0.0);

        var shadow_probe = vertex.probe.clone(light.shadowRay(isec.offsetP(light_sample.wi), light_sample, worker.scene));

        const tr = worker.visibility(&shadow_probe, isec, &vertex.interfaces, sampler) orelse return @splat(0.0);

        const radiance = light.evaluateTo(p, light_sample, sampler, worker.scene);

        const bxdf_result = mat_sample.evaluate(light_sample.wi, split);

        const light_pdf = light_sample.pdf() * light_weight;
        const weight: Vec4f = @splat(hlp.predividedPowerHeuristic(light_pdf, bxdf_result.pdf()));

        return weight * (tr * radiance * bxdf_result.reflection);
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

        const p = vertex.origin;
        const wo = -vertex.probe.ray.direction;
        const energy = isec.evaluateRadiance(p, wo, sampler, scene) orelse return @splat(0.0);

        const light_id = isec.lightId(scene);
        if (vertex.state.treat_as_singular or !Light.isLight(light_id)) {
            return energy;
        }

        const translucent = vertex.state.is_translucent;
        const split = self.splitting(vertex.probe.depth - 1);

        const light_pick = scene.lightPdfSpatial(light_id, p, vertex.geo_n, translucent, split);
        const light = scene.light(light_pick.offset);

        const pdf = light.pdf(vertex, isec, scene);
        const weight: Vec4f = @splat(hlp.powerHeuristic(vertex.bxdf_pdf, pdf * light_pick.pdf));

        return weight * energy;
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
