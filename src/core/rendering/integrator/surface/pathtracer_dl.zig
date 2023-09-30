const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Intersector = Vertex.Intersector;
const Scene = @import("../../../scene/scene.zig").Scene;
const Worker = @import("../../worker.zig").Worker;
const Light = @import("../../../scene/light/light.zig").Light;
const CausticsResolve = @import("../../../scene/renderstate.zig").CausticsResolve;
const hlp = @import("../helper.zig");
const MaterialSample = @import("../../../scene/material/sample.zig").Sample;
const bxdf = @import("../../../scene/material/bxdf.zig");
const ro = @import("../../../scene/ray_offset.zig");
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

        avoid_caustics: bool,
        caustics_resolve: CausticsResolve,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: *const Self, vertex: *Vertex, worker: *Worker) Vec4f {
        var throughput: Vec4f = @splat(1.0);
        var old_throughput: Vec4f = @splat(1.0);
        var result: Vec4f = @splat(0.0);

        var bxdf_samples: bxdf.Samples = undefined;

        while (true) {
            var sampler = worker.pickSampler(vertex.isec.depth);

            if (!worker.nextEvent(vertex, throughput, sampler)) {
                break;
            }

            throughput *= vertex.isec.hit.vol_tr;

            const wo = -vertex.isec.ray.direction;

            var pure_emissive: bool = undefined;
            const energy: Vec4f = vertex.isec.evaluateRadiance(
                wo,
                sampler,
                worker.scene,
                &pure_emissive,
            ) orelse @splat(0.0);

            if (vertex.state.treat_as_singular or !Light.isLight(vertex.isec.hit.lightId(worker.scene))) {
                result += throughput * energy;
            }

            if (pure_emissive or vertex.isec.depth >= self.settings.max_bounces) {
                break;
            }

            if (vertex.isec.depth >= self.settings.min_bounces) {
                if (hlp.russianRoulette(&throughput, old_throughput, sampler.sample1D())) {
                    break;
                }
            }

            const caustics = self.causticsResolve(vertex.state);

            const mat_sample = worker.sampleMaterial(vertex, sampler, 0.0, caustics);

            if (worker.aov.active()) {
                worker.commonAOV(throughput, vertex, &mat_sample);
            }

            result += throughput * self.directLight(vertex, &mat_sample, sampler, worker);

            const sample_result = mat_sample.sample(sampler, false, &bxdf_samples)[0];
            if (0.0 == sample_result.pdf or math.allLessEqualZero3(sample_result.reflection)) {
                break;
            }

            if (sample_result.class.specular) {
                if (.Full != caustics) {
                    break;
                }

                vertex.state.treat_as_singular = true;
            } else if (!sample_result.class.straight) {
                vertex.state.treat_as_singular = false;
                vertex.state.primary_ray = false;
            }

            old_throughput = throughput;
            throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

            if (!(sample_result.class.straight and sample_result.class.transmission)) {
                vertex.isec.depth += 1;
            }

            if (sample_result.class.straight) {
                vertex.isec.ray.setMinMaxT(vertex.isec.hit.offsetT(vertex.isec.ray.maxT()), ro.Ray_max_t);
            } else {
                vertex.isec.ray.origin = vertex.isec.hit.offsetP(sample_result.wi);
                vertex.isec.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                vertex.state.direct = false;
                vertex.state.from_subsurface = vertex.isec.hit.subsurface();
            }

            if (0.0 == vertex.isec.wavelength) {
                vertex.isec.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                vertex.interfaceChange(sample_result.wi, sampler, worker.scene);
            }

            vertex.state.transparent = vertex.state.transparent and (sample_result.class.transmission or sample_result.class.straight);

            sampler.incrementPadding();
        }

        return hlp.composeAlpha(result, throughput, vertex.state.transparent);
    }

    fn directLight(
        self: *const Self,
        vertex: *const Vertex,
        mat_sample: *const MaterialSample,
        sampler: *Sampler,
        worker: *Worker,
    ) Vec4f {
        var result: Vec4f = @splat(0.0);

        if (!mat_sample.canEvaluate()) {
            return result;
        }

        const n = mat_sample.super().geometricNormal();
        const p = vertex.isec.hit.p;

        const translucent = mat_sample.isTranslucent();

        const select = sampler.sample1D();
        const split = self.splitting(vertex.isec.depth);

        var lights_buffer: Scene.Lights = undefined;
        const lights = worker.scene.randomLightSpatial(p, n, translucent, select, split, &lights_buffer);

        for (lights) |l| {
            const light = worker.scene.light(l.offset);
            const light_sample = light.sampleTo(
                p,
                n,
                vertex.isec.time,
                translucent,
                sampler,
                worker.scene,
            ) orelse continue;

            var shadow_isec = Intersector.initFrom(
                light.shadowRay(vertex.isec.hit.offsetP(light_sample.wi), light_sample, worker.scene),
                &vertex.isec,
            );

            const tr = worker.visibility(&shadow_isec, &vertex.interfaces, sampler) orelse continue;

            const bxdf_result = mat_sample.evaluate(light_sample.wi, false);

            const radiance = light.evaluateTo(p, light_sample, sampler, worker.scene);

            const weight = 1.0 / (l.pdf * light_sample.pdf());

            result += @as(Vec4f, @splat(weight)) * (tr * radiance * bxdf_result.reflection);
        }

        return result;
    }

    fn splitting(self: *const Self, bounce: u32) bool {
        return .Adaptive == self.settings.light_sampling and bounce < 3;
    }

    fn causticsResolve(self: *const Self, state: Vertex.State) CausticsResolve {
        const pr = state.primary_ray;
        const r = self.settings.caustics_resolve;

        if (!pr) {
            if (self.settings.avoid_caustics) {
                return .Off;
            }

            return r;
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
