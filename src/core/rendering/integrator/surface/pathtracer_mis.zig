const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const Filter = @import("../../../image/texture/sampler.zig").Filter;
const Light = @import("../../../scene/light/light.zig").Light;
const Max_lights = @import("../../../scene/light/tree.zig").Tree.Max_lights;
const hlp = @import("../helper.zig");
const BxdfSample = @import("../../../scene/material/bxdf.zig").Sample;
const mat = @import("../../../scene/material/material.zig");
const scn = @import("../../../scene/constants.zig");
const ro = @import("../../../scene/ray_offset.zig");
const smp = @import("../../../sampler/sampler.zig");
const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const Flags = base.flags.Flags;

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

    pub const State = enum(u32) {
        PrimaryRay = 1 << 0,
        TreatAsSingular = 1 << 1,
        IsTranslucent = 1 << 2,
        SplitPhoton = 1 << 3,
        Direct = 1 << 4,
        FromSubsurface = 1 << 5,
    };

    const PathState = Flags(State);

    settings: Settings,

    samplers: [2 * Num_dedicated_samplers + 1]smp.Sampler,

    const Self = @This();

    pub fn init(alloc: Allocator, settings: Settings, max_samples_per_pixel: u32) !Self {
        const total_samples_per_pixel = settings.num_samples * max_samples_per_pixel;

        return Self{
            .settings = settings,
            .samplers = .{
                .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, 1, 2, total_samples_per_pixel) },
                .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, Max_lights + 1, Max_lights, total_samples_per_pixel) },
                .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, 1, 2, total_samples_per_pixel) },
                .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, Max_lights + 1, Max_lights, total_samples_per_pixel) },
                .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, 1, 2, total_samples_per_pixel) },
                .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, Max_lights + 1, Max_lights, total_samples_per_pixel) },
                .{ .Random = .{} },
            },
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        for (self.samplers) |*s| {
            s.deinit(alloc);
        }
    }

    pub fn startPixel(self: *Self) void {
        for (self.samplers) |*s| {
            s.startPixel();
        }
    }

    pub fn li(
        self: *Self,
        ray: *Ray,
        isec: *Intersection,
        gather_photons: bool,
        worker: *Worker,
        initial_stack: InterfaceStack,
    ) Vec4f {
        const num_samples = self.settings.num_samples;
        const num_samples_reciprocal = 1.0 / @intToFloat(f32, num_samples);

        const consider_photons = self.settings.photons_not_only_through_specular and gather_photons;

        var result = @splat(4, @as(f32, 0.0));

        var i = num_samples;
        while (i > 0) : (i -= 1) {
            worker.super.resetInterfaceStack(initial_stack);

            const gather_photons_here = num_samples == i and consider_photons;

            var split_ray = ray.*;
            var split_isec = isec.*;

            result += @splat(4, num_samples_reciprocal) * self.integrate(
                &split_ray,
                &split_isec,
                gather_photons_here,
                worker,
            );
        }

        return result;
    }

    fn integrate(self: *Self, ray: *Ray, isec: *Intersection, gather_photons: bool, worker: *Worker) Vec4f {
        const max_bounces = self.settings.max_bounces;

        var sample_result = BxdfSample{};

        var state = PathState{};
        state.set(.PrimaryRay, true);
        state.set(.TreatAsSingular, true);
        state.set(.Direct, true);

        var throughput = @splat(4, @as(f32, 1.0));
        var result = @splat(4, @as(f32, 0.0));
        var geo_n = @splat(4, @as(f32, 0.0));
        var wo1 = @splat(4, @as(f32, 0.0));

        var i: u32 = 0;
        while (true) : (i += 1) {
            const wo = -ray.ray.direction;

            const pr = state.is(.PrimaryRay);

            const filter: ?Filter = if (ray.depth <= 1 or pr) null else .Nearest;
            const avoid_caustics = self.settings.avoid_caustics and !pr;
            const straight_border = state.is(.FromSubsurface);

            const mat_sample = worker.super.sampleMaterial(
                ray.*,
                wo,
                wo1,
                isec.*,
                filter,
                0.0,
                avoid_caustics,
                straight_border,
            );

            wo1 = wo;

            // Only check direct eye-light connections for the very first hit.
            // Subsequent hits are handled by MIS.
            if (0 == i and mat_sample.super().sameHemisphere(wo)) {
                result += throughput * mat_sample.super().radiance;
            }

            if (mat_sample.isPureEmissive()) {
                state.unset(.Direct);
                break;
            }

            result += throughput * self.sampleLights(ray.*, isec.*, mat_sample, filter, worker);

            var effective_bxdf_pdf = sample_result.pdf;

            sample_result = mat_sample.sample(self.materialSampler(ray.depth), &worker.super.rng);
            if (0.0 == sample_result.pdf) {
                break;
            }

            if (sample_result.typef.is(.Specular)) {
                if (avoid_caustics) {
                    break;
                }

                state.set(.TreatAsSingular, true);
            } else if (sample_result.typef.no(.Straight)) {
                state.unset(.TreatAsSingular);

                effective_bxdf_pdf = sample_result.pdf;

                if (state.is(.PrimaryRay)) {
                    state.unset(.PrimaryRay);

                    const indirect = state.no(.Direct) and 0 != ray.depth;
                    if (gather_photons or indirect) {
                        worker.addPhoton(throughput * worker.photonLi(isec.*, mat_sample));
                    }
                }
            }

            if (!sample_result.typef.equals(.StraightTransmission)) {
                ray.depth += 1;
            }

            if (sample_result.typef.is(.Straight)) {
                ray.ray.setMinT(ro.offsetF(ray.ray.maxT()));
            } else {
                ray.ray.origin = isec.offsetP(sample_result.wi);
                ray.ray.setDirection(sample_result.wi);

                state.unset(.Direct);
                state.unset(.FromSubsurface);
            }

            ray.ray.setMaxT(scn.Ray_max_t);

            if (0.0 == ray.wavelength) {
                ray.wavelength = sample_result.wavelength;
            }

            throughput *= sample_result.reflection / @splat(4, sample_result.pdf);

            if (sample_result.typef.is(.Transmission)) {
                worker.super.interfaceChange(sample_result.wi, isec.*);
            }

            state.orSet(.FromSubsurface, isec.subsurface);

            if (sample_result.typef.is(.Straight) and state.no(.TreatAsSingular)) {
                sample_result.pdf = effective_bxdf_pdf;
            } else {
                state.set(.IsTranslucent, mat_sample.isTranslucent());
                geo_n = mat_sample.super().geometricNormal();
            }

            if (!worker.super.interface_stack.empty()) {
                const vr = worker.volume(ray, isec, filter);

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
                            worker.*,
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
            } else if (!worker.super.intersectAndResolveMask(ray, filter, isec)) {
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
                worker.*,
                &pure_emissive,
            );

            result += throughput * radiance;

            if (pure_emissive) {
                state.andSet(.Direct, !isec.visibleInCamera(worker.super) and ray.ray.maxT() >= scn.Ray_max_t);
                break;
            }

            if (ray.depth >= self.settings.max_bounces) {
                break;
            }

            if (ray.depth >= self.settings.min_bounces) {
                if (hlp.russianRoulette(&throughput, self.defaultSampler().sample1D(&worker.super.rng, 0))) {
                    break;
                }
            }
        }

        return hlp.composeAlpha(result, throughput, state.is(.Direct));
    }

    fn sampleLights(
        self: *Self,
        ray: Ray,
        isec: Intersection,
        mat_sample: mat.Sample,
        filter: ?Filter,
        worker: *Worker,
    ) Vec4f {
        var result = @splat(4, @as(f32, 0.0));

        if (!mat_sample.canEvaluate()) {
            return result;
        }

        const translucent = mat_sample.isTranslucent();

        const n = mat_sample.super().geometricNormal();
        const p = isec.offsetPN(n, translucent);

        var sampler = self.lightSampler(ray.depth);
        const select = sampler.sample1D(&worker.super.rng, worker.super.lights.len);
        const split = self.splitting(ray.depth);

        const lights = worker.super.scene.randomLightSpatial(p, n, translucent, select, split, &worker.super.lights);

        for (lights) |l, i| {
            const light = worker.super.scene.light(l.offset);

            result += self.evaluateLight(light, l.pdf, ray, p, i, isec, mat_sample, filter, worker);
        }

        return result;
    }

    fn evaluateLight(
        self: *Self,
        light: Light,
        light_weight: f32,
        history: Ray,
        p: Vec4f,
        sampler_d: usize,
        isec: Intersection,
        mat_sample: mat.Sample,
        filter: ?Filter,
        worker: *Worker,
    ) Vec4f {
        // Light source importance sample
        const light_sample = light.sampleTo(
            p,
            mat_sample.super().geometricNormal(),
            history.time,
            mat_sample.isTranslucent(),
            self.lightSampler(history.depth),
            sampler_d,
            &worker.super,
        ) orelse return @splat(4, @as(f32, 0.0));

        var shadow_ray = Ray.init(
            p,
            light_sample.wi,
            p[3],
            light_sample.t(),
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

        const radiance = light.evaluateTo(light_sample, .Nearest, worker.super);

        const light_pdf = light_sample.pdf() * light_weight;
        const weight = hlp.predividedPowerHeuristic(light_pdf, bxdf.pdf());

        return @splat(4, weight) * (tr * radiance * bxdf.reflection);
    }

    fn connectLight(
        self: Self,
        ray: Ray,
        geo_n: Vec4f,
        isec: Intersection,
        sample_result: BxdfSample,
        state: PathState,
        filter: ?Filter,
        worker: Worker,
        pure_emissive: *bool,
    ) Vec4f {
        const scene_worker = worker.super;

        const light_id = isec.lightId(scene_worker);
        if (!Light.isAreaLight(light_id)) {
            pure_emissive.* = false;
            return @splat(4, @as(f32, 0.0));
        }

        const wo = -sample_result.wi;

        const ls_energy = isec.evaluateRadiance(
            wo,
            filter,
            worker.super,
            pure_emissive,
        ) orelse return @splat(4, @as(f32, 0.0));

        if (state.is(.TreatAsSingular)) {
            return ls_energy;
        }

        const translucent = state.is(.IsTranslucent);
        const split = self.splitting(ray.depth);

        const light_pick = scene_worker.scene.lightPdfSpatial(light_id, ray.ray.origin, geo_n, translucent, split);
        const light = scene_worker.scene.light(light_pick.offset);

        const ls_pdf = light.pdf(ray, geo_n, isec, translucent, scene_worker);
        const weight = hlp.powerHeuristic(sample_result.pdf, ls_pdf * light_pick.pdf);

        return @splat(4, weight) * ls_energy;
    }

    fn connectVolumeLight(
        self: Self,
        ray: Ray,
        geo_n: Vec4f,
        isec: Intersection,
        bxdf_pdf: f32,
        state: PathState,
        worker: Worker,
    ) f32 {
        const scene_worker = worker.super;

        const light_id = isec.lightId(scene_worker);
        if (!Light.isLight(light_id)) {
            return 0.0;
        }

        if (state.is(.TreatAsSingular)) {
            return 1.0;
        }

        const translucent = state.is(.IsTranslucent);
        const split = self.splitting(ray.depth);

        const light_pick = scene_worker.scene.lightPdfSpatial(light_id, ray.ray.origin, geo_n, translucent, split);
        const light = scene_worker.scene.light(light_pick.offset);

        const ls_pdf = light.pdf(ray, geo_n, isec, translucent, scene_worker);

        return hlp.powerHeuristic(bxdf_pdf, ls_pdf * light_pick.pdf);
    }

    fn materialSampler(self: *Self, bounce: u32) *smp.Sampler {
        if (Num_dedicated_samplers > bounce) {
            return &self.samplers[2 * bounce];
        }

        return &self.samplers[2 * Num_dedicated_samplers];
    }

    fn lightSampler(self: *Self, bounce: u32) *smp.Sampler {
        if (Num_dedicated_samplers > bounce) {
            return &self.samplers[2 * bounce + 1];
        }

        return &self.samplers[2 * Num_dedicated_samplers];
    }

    fn defaultSampler(self: *Self) *smp.Sampler {
        return &self.samplers[2 * Num_dedicated_samplers];
    }

    fn splitting(self: Self, bounce: u32) bool {
        return .Adaptive == self.settings.light_sampling and
            bounce < Num_dedicated_samplers;
    }
};

pub const Factory = struct {
    settings: PathtracerMIS.Settings = .{ .num_samples = 1, .radius = 1.0 },

    pub fn create(self: Factory, alloc: Allocator, max_samples_per_pixel: u32) !PathtracerMIS {
        return try PathtracerMIS.init(alloc, self.settings, max_samples_per_pixel);
    }
};
