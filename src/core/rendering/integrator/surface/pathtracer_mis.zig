const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Intersector = Vertex.Intersector;
const Scene = @import("../../../scene/scene.zig").Scene;
const Light = @import("../../../scene/light/light.zig").Light;
const CausticsResolve = @import("../../../scene/renderstate.zig").CausticsResolve;
const BxdfSample = @import("../../../scene/material/bxdf.zig").Sample;
const MaterialSample = @import("../../../scene/material/sample.zig").Sample;
const ro = @import("../../../scene/ray_offset.zig");
const Worker = @import("../../worker.zig").Worker;
const hlp = @import("../helper.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PathtracerMIS = struct {
    pub const Settings = struct {
        min_bounces: u32,
        max_bounces: u32,

        light_sampling: hlp.LightSampling,
        caustics_path: hlp.CausticsPath,
        caustics_resolve: CausticsResolve,
        photons_not_only_through_specular: bool,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: *const Self, vertex: *Vertex, gather_photons: bool, worker: *Worker) Vec4f {
        const max_bounces = self.settings.max_bounces;

        var throughput: Vec4f = @splat(1.0);
        var old_throughput: Vec4f = @splat(1.0);
        var result: Vec4f = @splat(0.0);

        while (true) {
            var sampler = worker.pickSampler(vertex.isec.depth);

            if (!worker.nextEvent(vertex, throughput, sampler)) {
                break;
            }

            throughput *= vertex.isec.hit.vol_tr;

            var pure_emissive: bool = undefined;
            const radiance = self.connectLight(vertex, sampler, worker.scene, &pure_emissive);

            result += throughput * radiance;

            if (pure_emissive) {
                const vis_in_cam = vertex.isec.hit.visibleInCamera(worker.scene);
                vertex.state.direct = vertex.state.direct and (!vis_in_cam and vertex.isec.ray.maxT() >= ro.Ray_max_t);
                break;
            }

            if (vertex.isec.depth >= max_bounces) {
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

            result += throughput * self.sampleLights(vertex, &mat_sample, sampler, worker);

            const sample_result = mat_sample.sample(sampler);
            if (0.0 == sample_result.pdf or math.allLessEqualZero3(sample_result.reflection)) {
                break;
            }

            if (sample_result.class.specular) {
                if (.Full != caustics) {
                    break;
                }

                vertex.state.treat_as_singular = true;

                if (vertex.state.primary_ray) {
                    vertex.state.started_specular = true;
                }
            } else if (!sample_result.class.straight) {
                vertex.state.treat_as_singular = false;
                if (vertex.state.primary_ray) {
                    vertex.state.primary_ray = false;

                    const indirect = !vertex.state.direct and 0 != vertex.isec.depth;
                    if (gather_photons and (self.settings.photons_not_only_through_specular or indirect)) {
                        worker.addPhoton(throughput * worker.photonLi(vertex.isec.hit, &mat_sample, sampler));
                    }
                }
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
                vertex.state.is_translucent = mat_sample.isTranslucent();
                vertex.bxdf_pdf = sample_result.pdf;
                vertex.geo_n = mat_sample.super().geometricNormal();
            }

            if (0.0 == vertex.isec.wavelength) {
                vertex.isec.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                vertex.interfaceChange(sample_result.wi, sampler, worker.scene);
            }

            sampler.incrementPadding();
        }

        return hlp.composeAlpha(result, throughput, vertex.state.direct);
    }

    fn sampleLights(
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

        const p = vertex.isec.hit.p;
        const n = mat_sample.super().geometricNormal();
        const translucent = mat_sample.isTranslucent();

        const select = sampler.sample1D();
        const split = self.splitting(vertex.isec.depth);

        var lights_buffer: Scene.Lights = undefined;
        const lights = worker.scene.randomLightSpatial(p, n, translucent, select, split, &lights_buffer);

        for (lights) |l| {
            const light = worker.scene.light(l.offset);

            result += evaluateLight(light, l.pdf, vertex, mat_sample, sampler, worker);
        }

        return result;
    }

    fn evaluateLight(
        light: Light,
        light_weight: f32,
        vertex: *const Vertex,
        mat_sample: *const MaterialSample,
        sampler: *Sampler,
        worker: *Worker,
    ) Vec4f {
        const p = vertex.isec.hit.p;

        const light_sample = light.sampleTo(
            p,
            mat_sample.super().geometricNormal(),
            vertex.isec.time,
            mat_sample.isTranslucent(),
            sampler,
            worker.scene,
        ) orelse return @splat(0.0);

        var shadow_isec = Intersector.initFrom(
            light.shadowRay(vertex.isec.hit.offsetP(light_sample.wi), light_sample, worker.scene),
            &vertex.isec,
        );

        const tr = worker.visibility(&shadow_isec, &vertex.interfaces, sampler) orelse return @splat(0.0);

        const bxdf = mat_sample.evaluate(light_sample.wi);

        const radiance = light.evaluateTo(p, light_sample, sampler, worker.scene);

        const light_pdf = light_sample.pdf() * light_weight;
        const weight = hlp.predividedPowerHeuristic(light_pdf, bxdf.pdf());

        return @as(Vec4f, @splat(weight)) * (tr * radiance * bxdf.reflection);
    }

    fn connectLight(
        self: *const Self,
        vertex: *const Vertex,
        sampler: *Sampler,
        scene: *const Scene,
        pure_emissive: *bool,
    ) Vec4f {
        const wo = -vertex.isec.ray.direction;
        const energy = vertex.isec.evaluateRadiance(
            wo,
            sampler,
            scene,
            pure_emissive,
        ) orelse return @splat(0.0);

        const light_id = vertex.isec.hit.lightId(scene);
        if (vertex.state.treat_as_singular or !Light.isLight(light_id)) {
            return energy;
        }

        const translucent = vertex.state.is_translucent;
        const split = self.splitting(vertex.isec.depth);

        const light_pick = scene.lightPdfSpatial(light_id, vertex.isec.ray.origin, vertex.geo_n, translucent, split);
        const light = scene.light(light_pick.offset);

        const pdf = light.pdf(vertex, scene);
        const weight = hlp.powerHeuristic(vertex.bxdf_pdf, pdf * light_pick.pdf);

        return @as(Vec4f, @splat(weight)) * energy;
    }

    fn splitting(self: *const Self, bounce: u32) bool {
        return .Adaptive == self.settings.light_sampling and bounce < 3;
    }

    fn causticsResolve(self: *const Self, state: Vertex.State) CausticsResolve {
        const pr = state.primary_ray;
        const p = self.settings.caustics_path;
        const r = self.settings.caustics_resolve;

        if (!pr) {
            if (.Off == p) {
                return .Off;
            } else if (.Indirect == p and !state.started_specular) {
                return .Off;
            }

            return r;
        }

        return .Full;
    }
};

pub const Factory = struct {
    settings: PathtracerMIS.Settings,

    pub fn create(self: Factory) PathtracerMIS {
        return .{ .settings = self.settings };
    }
};
