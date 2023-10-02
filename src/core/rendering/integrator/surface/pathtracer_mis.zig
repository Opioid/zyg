const vt = @import("../../../scene/vertex.zig");
const Vertex = vt.Vertex;
const VertexPool = vt.Pool;
const Scene = @import("../../../scene/scene.zig").Scene;
const Light = @import("../../../scene/light/light.zig").Light;
const CausticsResolve = @import("../../../scene/renderstate.zig").CausticsResolve;
const MaterialSample = @import("../../../scene/material/sample.zig").Sample;
const bxdf = @import("../../../scene/material/bxdf.zig");
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

    pub fn li(self: *const Self, input: *Vertex, gather_photons: bool, worker: *Worker) Vec4f {
        const max_bounces = self.settings.max_bounces;

        var result: Vec4f = @splat(0.0);

        var vertices: VertexPool = .{};
        vertices.start(input.*);

        var bxdf_samples: bxdf.Samples = undefined;

        while (vertices.iterate()) {
            while (vertices.consume()) |vertex| {
                var sampler = worker.pickSampler(vertex.isec.depth);

                if (!worker.nextEvent(vertex, vertex.throughput, sampler)) {
                    continue;
                }

                vertex.throughput *= vertex.isec.hit.vol_tr;

                var pure_emissive: bool = undefined;
                const radiance = self.connectLight(vertex, sampler, worker.scene, &pure_emissive);

                const vertex_weight = vertex.throughput * @as(Vec4f, @splat(vertex.split_weight));

                result += vertex_weight * radiance;

                if (pure_emissive or vertex.isec.depth >= max_bounces) {
                    continue;
                }

                if (vertex.isec.depth >= self.settings.min_bounces) {
                    if (hlp.russianRoulette(&vertex.throughput, vertex.throughput_old, sampler.sample1D())) {
                        continue;
                    }
                }

                const caustics = self.causticsResolve(vertex.state);

                const mat_sample = worker.sampleMaterial(vertex, sampler, 0.0, caustics);

                if (worker.aov.active()) {
                    worker.commonAOV(vertex.throughput, vertex, &mat_sample);
                }

                const indirect = !vertex.state.direct and 0 != vertex.isec.depth;
                if (gather_photons and vertex.state.primary_ray and mat_sample.canEvaluate() and (self.settings.photons_not_only_through_specular or indirect)) {
                    worker.addPhoton(vertex_weight * worker.photonLi(vertex.isec.hit, &mat_sample, sampler));
                }

                // Only potentially split for SSS case or on the first bounce
                const split = vertex.path_count < 2 and
                    ((vertex.isec.depth < 3 and !vertex.interfaces.empty()) or
                    (vertex.isec.depth < 2 and vertex.isec.hit.event != .Scatter));

                //  const split = false;

                result += vertex_weight * self.sampleLights(vertex, &mat_sample, split, sampler, worker);

                const sample_results = mat_sample.sample(sampler, split, &bxdf_samples);
                const path_count: u32 = @intCast(sample_results.len);

                for (sample_results) |sample_result| {
                    if (0.0 == sample_result.pdf or
                        math.allLessEqualZero3(sample_result.reflection) or
                        (sample_result.class.specular and .Full != caustics))
                    {
                        continue;
                    }

                    const next_path_count = vertex.path_count * path_count;
                    const next_split_weight = vertex.split_weight * sample_result.split_weight;

                    var next_vertex = vertices.new(vertex.*);

                    next_vertex.path_count = next_path_count;
                    next_vertex.split_weight = next_split_weight;

                    if (sample_result.class.specular) {
                        next_vertex.state.treat_as_singular = true;

                        if (next_vertex.state.primary_ray) {
                            next_vertex.state.started_specular = true;
                        }
                    } else if (!sample_result.class.straight) {
                        next_vertex.state.treat_as_singular = false;
                        next_vertex.state.primary_ray = false;
                    }

                    next_vertex.throughput_old = next_vertex.throughput;
                    next_vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

                    if (!(sample_result.class.straight and sample_result.class.transmission)) {
                        next_vertex.isec.depth += 1;
                    }

                    if (sample_result.class.straight) {
                        next_vertex.isec.ray.setMinMaxT(next_vertex.isec.hit.offsetT(next_vertex.isec.ray.maxT()), ro.Ray_max_t);
                    } else {
                        next_vertex.isec.ray.origin = next_vertex.isec.hit.offsetP(sample_result.wi);
                        next_vertex.isec.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                        next_vertex.state.direct = false;
                        next_vertex.state.from_subsurface = next_vertex.isec.hit.subsurface();
                        next_vertex.state.is_translucent = mat_sample.isTranslucent();
                        next_vertex.bxdf_pdf = sample_result.pdf;
                        next_vertex.geo_n = mat_sample.super().geometricNormal();
                    }

                    if (0.0 == vertex.isec.wavelength) {
                        next_vertex.isec.wavelength = sample_result.wavelength;
                    }

                    if (sample_result.class.transmission) {
                        next_vertex.interfaceChange(sample_result.wi, sampler, worker.scene);
                    }

                    next_vertex.state.transparent = next_vertex.state.transparent and (sample_result.class.transmission or sample_result.class.straight);
                }

                sampler.incrementPadding();
            }
        }

        // return hlp.composeAlpha(result, throughput, vertex.state.direct);
        //    return hlp.composeAlpha(result, @splat(1.0), false);

        return .{ result[0], result[1], result[2], vertices.alpha };
    }

    fn sampleLights(
        self: *const Self,
        vertex: *const Vertex,
        mat_sample: *const MaterialSample,
        material_split: bool,
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

            result += evaluateLight(light, l.pdf, vertex, mat_sample, material_split, sampler, worker);
        }

        return result;
    }

    fn evaluateLight(
        light: Light,
        light_weight: f32,
        vertex: *const Vertex,
        mat_sample: *const MaterialSample,
        split: bool,
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

        var shadow_isec = Vertex.Intersector.initFrom(
            light.shadowRay(vertex.isec.hit.offsetP(light_sample.wi), light_sample, worker.scene),
            &vertex.isec,
        );

        const tr = worker.visibility(&shadow_isec, &vertex.interfaces, sampler) orelse return @splat(0.0);

        const bxdf_result = mat_sample.evaluate(light_sample.wi, split);

        const radiance = light.evaluateTo(p, light_sample, sampler, worker.scene);

        const light_pdf = light_sample.pdf() * light_weight;
        const weight = hlp.predividedPowerHeuristic(light_pdf, bxdf_result.pdf());

        return @as(Vec4f, @splat(weight)) * (tr * radiance * bxdf_result.reflection);
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
