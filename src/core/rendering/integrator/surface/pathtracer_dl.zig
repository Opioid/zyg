const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const Light = @import("../../../scene/light/light.zig").Light;
const Max_lights = @import("../../../scene/light/light_tree.zig").Tree.Max_lights;
const CausticsResolve = @import("../../../scene/renderstate.zig").CausticsResolve;
const hlp = @import("../helper.zig");
const MaterialSample = @import("../../../scene/material/sample.zig").Sample;
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

        var isec = Intersection{};

        while (true) {
            var sampler = worker.pickSampler(vertex.depth);

            if (!worker.nextEvent(vertex, throughput, &isec, sampler)) {
                break;
            }

            throughput *= isec.volume.tr;

            const wo = -vertex.ray.direction;

            var pure_emissive: bool = undefined;
            const energy: Vec4f = isec.evaluateRadiance(
                vertex.ray.origin,
                wo,
                sampler,
                worker.scene,
                &pure_emissive,
            ) orelse @splat(0.0);

            if (vertex.state.treat_as_singular or !Light.isLight(isec.lightId(worker.scene))) {
                result += throughput * energy;
            }

            if (pure_emissive) {
                const vis_in_cam = isec.visibleInCamera(worker.scene);
                vertex.state.direct = vertex.state.direct and (!vis_in_cam and vertex.ray.maxT() >= ro.Ray_max_t);
                break;
            }

            if (vertex.depth >= self.settings.max_bounces) {
                break;
            }

            if (vertex.depth >= self.settings.min_bounces) {
                if (hlp.russianRoulette(&throughput, old_throughput, sampler.sample1D())) {
                    break;
                }
            }

            const caustics = self.causticsResolve(vertex.state);

            const mat_sample = worker.sampleMaterial(
                vertex.*,
                isec,
                sampler,
                0.0,
                caustics,
            );

            if (worker.aov.active()) {
                worker.commonAOV(throughput, vertex.*, isec, &mat_sample);
            }

            result += throughput * self.directLight(vertex.*, isec, &mat_sample, sampler, worker);

            const sample_result = mat_sample.sample(sampler);
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
                vertex.depth += 1;
            }

            if (sample_result.class.straight) {
                vertex.ray.setMinMaxT(isec.offsetT(vertex.ray.maxT()), ro.Ray_max_t);
            } else {
                vertex.ray.origin = isec.offsetP(sample_result.wi);
                vertex.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                vertex.state.direct = false;
                vertex.state.from_subsurface = isec.subsurface();
            }

            if (0.0 == vertex.wavelength) {
                vertex.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                worker.interfaceChange(sample_result.wi, isec, sampler);
            }

            sampler.incrementPadding();
        }

        return hlp.composeAlpha(result, throughput, vertex.state.direct);
    }

    fn directLight(
        self: *const Self,
        vertex: Vertex,
        isec: Intersection,
        mat_sample: *const MaterialSample,
        sampler: *Sampler,
        worker: *Worker,
    ) Vec4f {
        var result: Vec4f = @splat(0.0);

        if (!mat_sample.canEvaluate()) {
            return result;
        }

        const translucent = mat_sample.isTranslucent();

        const n = mat_sample.super().geometricNormal();
        const p = isec.offsetPN(n, translucent);

        var shadow_vertex: Vertex = undefined;
        shadow_vertex.depth = vertex.depth;
        shadow_vertex.time = vertex.time;
        shadow_vertex.wavelength = vertex.wavelength;

        const select = sampler.sample1D();
        const split = self.splitting(vertex.depth);

        const lights = worker.randomLightSpatial(p, n, translucent, select, split);

        for (lights) |l| {
            const light = worker.scene.light(l.offset);
            const light_sample = light.sampleTo(
                p,
                n,
                vertex.time,
                translucent,
                sampler,
                worker.scene,
            ) orelse continue;

            shadow_vertex.ray.origin = p;
            shadow_vertex.ray.setDirection(light_sample.wi, light_sample.offset());
            const tr = worker.visibility(&shadow_vertex, isec, sampler) orelse continue;

            const bxdf = mat_sample.evaluate(light_sample.wi);

            const radiance = light.evaluateTo(p, light_sample, sampler, worker.scene);

            const weight = 1.0 / (l.pdf * light_sample.pdf());

            result += @as(Vec4f, @splat(weight)) * (tr * radiance * bxdf.reflection);
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
