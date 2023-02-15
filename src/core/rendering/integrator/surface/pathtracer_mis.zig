const Ray = @import("../../../scene/ray.zig").Ray;
const Scene = @import("../../../scene/scene.zig").Scene;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const Filter = @import("../../../image/texture/texture_sampler.zig").Filter;
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
    const Num_dedicated_samplers = 3;

    pub const Settings = struct {
        num_samples: u32,
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
        const os = sample *% self.settings.num_samples;
        for (self.samplers) |*s| {
            s.startPixel(os, seed);
        }
    }

    pub fn li(
        self: *Self,
        ray: *Ray,
        isec: *Intersection,
        gather_photons: bool,
        worker: *Worker,
        initial_stack: *const InterfaceStack,
    ) Vec4f {
        const num_samples = self.settings.num_samples;
        const num_samples_reciprocal = 1.0 / @intToFloat(f32, num_samples);

        var result = @splat(4, @as(f32, 0.0));

        var i = num_samples;
        while (i > 0) : (i -= 1) {
            worker.resetInterfaceStack(initial_stack);

            var split_ray = ray.*;
            var split_isec = isec.*;

            result += @splat(4, num_samples_reciprocal) * self.integrate(
                &split_ray,
                &split_isec,
                num_samples == i and gather_photons,
                worker,
            );

            for (self.samplers) |*s| {
                s.incrementSample();
            }
        }

        return result;
    }

    fn integrate(self: *Self, ray: *Ray, isec: *Intersection, gather_photons: bool, worker: *Worker) Vec4f {
        const max_bounces = self.settings.max_bounces;

        var sample_result = BxdfSample{};

        var state = PathState{};

        var throughput = @splat(4, @as(f32, 1.0));
        var result = @splat(4, @as(f32, 0.0));
        var geo_n = @splat(4, @as(f32, 0.0));
        var wo1 = @splat(4, @as(f32, 0.0));

        {
            var pure_emissive: bool = undefined;
            const energy = isec.evaluateRadiance(
                ray.ray.origin,
                -ray.ray.direction,
                null,
                worker.scene,
                &pure_emissive,
            ) orelse @splat(4, @as(f32, 0.0));

            if (pure_emissive) {
                return hlp.composeAlpha(energy, throughput, false);
            }

            result += energy;
        }

        var i: u32 = 0;
        while (true) : (i += 1) {
            const wo = -ray.ray.direction;

            const pr = state.primary_ray;

            const filter: ?Filter = if (ray.depth <= 1 or pr) null else .Nearest;
            const avoid_caustics = self.settings.avoid_caustics and !pr;
            const straight_border = state.from_subsurface;

            const mat_sample = worker.sampleMaterial(
                ray.*,
                wo,
                wo1,
                isec.*,
                filter,
                0.0,
                avoid_caustics,
                straight_border,
            );

            if (worker.aov.active()) {
                worker.commonAOV(throughput, ray.*, isec.*, &mat_sample, pr);
            }

            wo1 = wo;

            var sampler = self.pickSampler(ray.depth);

            result += throughput * self.sampleLights(ray.*, isec.*, &mat_sample, filter, sampler, worker);

            var effective_bxdf_pdf = sample_result.pdf;

            sample_result = mat_sample.sample(sampler);
            if (0.0 == sample_result.pdf) {
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
                        worker.addPhoton(throughput * worker.photonLi(isec.*, &mat_sample));
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

            const old_throughput = throughput;
            throughput *= sample_result.reflection / @splat(4, sample_result.pdf);

            if (sample_result.class.transmission) {
                worker.interfaceChange(sample_result.wi, isec.*);
            }

            state.from_subsurface = state.from_subsurface or isec.subsurface;

            if (sample_result.class.straight and !state.treat_as_singular) {
                sample_result.pdf = effective_bxdf_pdf;
            } else {
                state.is_translucent = mat_sample.isTranslucent();
                geo_n = mat_sample.super().geometricNormal();
            }

            if (!worker.interface_stack.empty()) {
                const vr = worker.volume(ray, throughput, isec, filter, sampler);

                if (.Absorb == vr.event) {
                    if (0 == ray.depth) {
                        // This is the direct eye-light connection for the volume case.
                        result += vr.li;
                    } else {
                        const w = self.connectVolumeLight(
                            ray.*,
                            geo_n,
                            isec.*,
                            effective_bxdf_pdf,
                            state,
                            worker.scene,
                        );

                        result += @splat(4, w) * (throughput * vr.li);
                    }

                    break;
                }

                // This is only needed for Tracking_single at the moment...
                result += throughput * vr.li;
                throughput *= vr.tr;

                if (.Abort == vr.event) {
                    break;
                }

                if (.Scatter == vr.event and ray.depth >= max_bounces) {
                    break;
                }
            } else if (!worker.intersectAndResolveMask(ray, filter, isec)) {
                break;
            }

            var pure_emissive: bool = undefined;
            const radiance = self.connectLight(
                ray.*,
                geo_n,
                isec.*,
                sample_result,
                state,
                filter,
                worker.scene,
                &pure_emissive,
            );

            result += throughput * radiance;

            if (pure_emissive) {
                state.direct = state.direct and (!isec.visibleInCamera(worker.scene) and ray.ray.maxT() >= ro.Ray_max_t);
                break;
            }

            if (ray.depth >= self.settings.max_bounces) {
                break;
            }

            if (ray.depth >= self.settings.min_bounces) {
                if (hlp.russianRoulette(&throughput, old_throughput, sampler.sample1D())) {
                    break;
                }
            }

            sampler.incrementPadding();
        }

        return hlp.composeAlpha(result, throughput, state.direct);
    }

    fn sampleLights(
        self: *const Self,
        ray: Ray,
        isec: Intersection,
        mat_sample: *const MaterialSample,
        filter: ?Filter,
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

            result += evaluateLight(light, l.pdf, ray, p, isec, mat_sample, filter, sampler, worker);
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
        filter: ?Filter,
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

        const tr = worker.transmitted(
            &shadow_ray,
            mat_sample.super().wo,
            isec,
            filter,
        ) orelse return @splat(4, @as(f32, 0.0));

        const bxdf = mat_sample.evaluate(light_sample.wi);

        const radiance = light.evaluateTo(p, light_sample, filter, worker.scene);

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
        filter: ?Filter,
        scene: *const Scene,
        pure_emissive: *bool,
    ) Vec4f {
        const wo = -sample_result.wi;
        const energy = isec.evaluateRadiance(
            ray.ray.origin,
            wo,
            filter,
            scene,
            pure_emissive,
        ) orelse return @splat(4, @as(f32, 0.0));

        const light_id = isec.lightId(scene);
        if (state.treat_as_singular or !Light.isAreaLight(light_id)) {
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

    fn connectVolumeLight(
        self: *const Self,
        ray: Ray,
        geo_n: Vec4f,
        isec: Intersection,
        bxdf_pdf: f32,
        state: PathState,
        scene: *const Scene,
    ) f32 {
        const light_id = isec.lightId(scene);

        if (state.treat_as_singular or !Light.isLight(light_id)) {
            return 1.0;
        }

        const translucent = state.is_translucent;
        const split = self.splitting(ray.depth);

        const light_pick = scene.lightPdfSpatial(light_id, ray.ray.origin, geo_n, translucent, split);
        const light = scene.light(light_pick.offset);

        const pdf = light.pdf(ray, geo_n, isec, translucent, scene);

        return hlp.powerHeuristic(bxdf_pdf, pdf * light_pick.pdf);
    }

    fn splitting(self: *const Self, bounce: u32) bool {
        return .Adaptive == self.settings.light_sampling and bounce < Num_dedicated_samplers;
    }

    fn pickSampler(self: *Self, bounce: u32) *Sampler {
        if (bounce < 4) {
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
