const Ray = @import("../../../scene/ray.zig").Ray;
const Scene = @import("../../../scene/scene.zig").Scene;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const Light = @import("../../../scene/light/light.zig").Light;
const Max_lights = @import("../../../scene/light/light_tree.zig").Tree.Max_lights;
const hlp = @import("../helper.zig");
const BxdfSample = @import("../../../scene/material/bxdf.zig").Sample;
const MaterialSample = @import("../../../scene/material/sample.zig").Sample;
const ro = @import("../../../scene/ray_offset.zig");
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

        avoid_caustics: bool,
        photons_not_only_through_specular: bool,
    };

    const PathState = packed struct {
        primary_ray: bool = true,
        treat_as_singular: bool = true,
        is_translucent: bool = false,
        split_photon: bool = false,
        direct: bool = true,
        from_subsurface: bool = false,
    };

    settings: Settings,

    samplers: [2]Sampler,

    const Self = @This();

    pub fn startPixel(self: *Self, sample: u32, seed: u32) void {
        for (&self.samplers) |*s| {
            s.startPixel(sample, seed);
        }
    }

    pub fn li(self: *Self, ray: *Ray, gather_photons: bool, worker: *Worker) Vec4f {
        const max_bounces = self.settings.max_bounces;

        var sample_result = BxdfSample{};

        var state = PathState{};

        var throughput = @splat(4, @as(f32, 1.0));
        var old_throughput = @splat(4, @as(f32, 1.0));
        var result = @splat(4, @as(f32, 0.0));
        var geo_n = @splat(4, @as(f32, 0.0));

        var isec = Intersection{};

        while (true) {
            const pr = state.primary_ray;

            var sampler = self.pickSampler(ray.depth);

            if (!worker.nextEvent(ray, throughput, &isec, sampler)) {
                break;
            }

            throughput *= isec.volume.tr;

            var pure_emissive: bool = undefined;
            const radiance = self.connectLight(
                ray.*,
                geo_n,
                isec,
                sample_result,
                state,
                sampler,
                worker.scene,
                &pure_emissive,
            );

            result += throughput * radiance;

            if (pure_emissive) {
                state.direct = state.direct and (!isec.visibleInCamera(worker.scene) and ray.ray.maxT() >= ro.Ray_max_t);
                break;
            }

            if (ray.depth >= max_bounces) {
                break;
            }

            if (ray.depth >= self.settings.min_bounces) {
                if (hlp.russianRoulette(&throughput, old_throughput, sampler.sample1D())) {
                    break;
                }
            }

            const wo = -ray.ray.direction;

            const avoid_caustics = self.settings.avoid_caustics and !pr;
            const straight_border = state.from_subsurface;

            const mat_sample = worker.sampleMaterial(
                ray.*,
                wo,
                isec,
                sampler,
                0.0,
                avoid_caustics,
                straight_border,
            );

            if (worker.aov.active()) {
                worker.commonAOV(throughput, ray.*, isec, &mat_sample, pr);
            }

            result += throughput * self.sampleLights(ray.*, isec, &mat_sample, sampler, worker);

            var effective_bxdf_pdf = sample_result.pdf;

            sample_result = mat_sample.sample(sampler);
            if (0.0 == sample_result.pdf or math.allLessEqualZero3(sample_result.reflection)) {
                break;
            }

            if (sample_result.class.specular) {
                if (avoid_caustics) {
                    break;
                }

                state.treat_as_singular = true;
            } else if (!sample_result.class.straight) {
                state.treat_as_singular = false;

                effective_bxdf_pdf = sample_result.pdf;

                if (pr) {
                    state.primary_ray = false;

                    const indirect = !state.direct and 0 != ray.depth;
                    if (gather_photons and (self.settings.photons_not_only_through_specular or indirect)) {
                        worker.addPhoton(throughput * worker.photonLi(isec, &mat_sample, sampler));
                    }
                }
            }

            if (!(sample_result.class.straight and sample_result.class.transmission)) {
                ray.depth += 1;
            }

            if (sample_result.class.straight) {
                ray.ray.setMinMaxT(ro.offsetF(ray.ray.maxT()), ro.Ray_max_t);
            } else {
                ray.ray.origin = isec.offsetP(sample_result.wi);
                ray.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                state.direct = false;
                state.from_subsurface = false;
            }

            if (0.0 == ray.wavelength) {
                ray.wavelength = sample_result.wavelength;
            }

            old_throughput = throughput;
            throughput *= sample_result.reflection / @splat(4, sample_result.pdf);

            if (sample_result.class.transmission) {
                worker.interfaceChange(sample_result.wi, isec, sampler);
            }

            state.from_subsurface = state.from_subsurface or isec.subsurface();

            if (sample_result.class.straight and !state.treat_as_singular) {
                sample_result.pdf = effective_bxdf_pdf;
            } else {
                state.is_translucent = mat_sample.isTranslucent();
                geo_n = mat_sample.super().geometricNormal();
            }

            sampler.incrementPadding();
        }

        for (&self.samplers) |*s| {
            s.incrementSample();
        }

        return hlp.composeAlpha(result, throughput, state.direct);
    }

    fn sampleLights(
        self: *const Self,
        ray: Ray,
        isec: Intersection,
        mat_sample: *const MaterialSample,
        sampler: *Sampler,
        worker: *Worker,
    ) Vec4f {
        var result = @splat(4, @as(f32, 0.0));

        if (!mat_sample.canEvaluate()) {
            return result;
        }

        const translucent = mat_sample.isTranslucent();

        const n = mat_sample.super().geometricNormal();
        const p = isec.offsetPN(n, translucent);

        const select = sampler.sample1D();
        const split = self.splitting(ray.depth);

        const lights = worker.randomLightSpatial(p, n, translucent, select, split);

        for (lights) |l| {
            const light = worker.scene.light(l.offset);

            result += evaluateLight(light, l.pdf, ray, p, isec, mat_sample, sampler, worker);
        }

        return result;
    }

    fn evaluateLight(
        light: Light,
        light_weight: f32,
        history: Ray,
        p: Vec4f,
        isec: Intersection,
        mat_sample: *const MaterialSample,
        sampler: *Sampler,
        worker: *Worker,
    ) Vec4f {
        // Light source importance sample
        const light_sample = light.sampleTo(
            p,
            mat_sample.super().geometricNormal(),
            history.time,
            mat_sample.isTranslucent(),
            sampler,
            worker.scene,
        ) orelse return @splat(4, @as(f32, 0.0));

        var shadow_ray = Ray.init(
            p,
            light_sample.wi,
            p[3],
            light_sample.offset(),
            history.depth,
            history.wavelength,
            history.time,
        );

        const tr = worker.visibility(&shadow_ray, isec, sampler) orelse return @splat(4, @as(f32, 0.0));

        const bxdf = mat_sample.evaluate(light_sample.wi);

        const radiance = light.evaluateTo(p, light_sample, sampler, worker.scene);

        const light_pdf = light_sample.pdf() * light_weight;
        const weight = hlp.predividedPowerHeuristic(light_pdf, bxdf.pdf());

        return @splat(4, weight) * (tr * radiance * bxdf.reflection);
    }

    fn connectLight(
        self: *const Self,
        ray: Ray,
        geo_n: Vec4f,
        isec: Intersection,
        sample_result: BxdfSample,
        state: PathState,
        sampler: *Sampler,
        scene: *const Scene,
        pure_emissive: *bool,
    ) Vec4f {
        const wo = -ray.ray.direction;
        const energy = isec.evaluateRadiance(
            ray.ray.origin,
            wo,
            sampler,
            scene,
            pure_emissive,
        ) orelse return @splat(4, @as(f32, 0.0));

        const light_id = isec.lightId(scene);
        if (state.treat_as_singular or !Light.isLight(light_id)) {
            return energy;
        }

        const translucent = state.is_translucent;
        const split = self.splitting(ray.depth);

        const light_pick = scene.lightPdfSpatial(light_id, ray.ray.origin, geo_n, translucent, split);
        const light = scene.light(light_pick.offset);

        const pdf = light.pdf(ray, geo_n, isec, translucent, scene);
        const weight = hlp.powerHeuristic(sample_result.pdf, pdf * light_pick.pdf);

        return @splat(4, weight) * energy;
    }

    fn splitting(self: *const Self, bounce: u32) bool {
        return .Adaptive == self.settings.light_sampling and bounce < 3;
    }

    fn pickSampler(self: *Self, bounce: u32) *Sampler {
        if (bounce < 3) {
            return &self.samplers[0];
        }

        return &self.samplers[1];
    }
};

pub const Factory = struct {
    settings: PathtracerMIS.Settings,

    pub fn create(self: Factory, rng: *RNG) PathtracerMIS {
        return .{
            .settings = self.settings,
            .samplers = .{ .{ .Sobol = .{} }, .{ .Random = .{ .rng = rng } } },
        };
    }
};
