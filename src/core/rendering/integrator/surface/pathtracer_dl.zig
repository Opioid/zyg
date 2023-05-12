const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const Filter = @import("../../../image/texture/texture_sampler.zig").Filter;
const Light = @import("../../../scene/light/light.zig").Light;
const Max_lights = @import("../../../scene/light/light_tree.zig").Tree.Max_lights;
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
    };

    settings: Settings,

    samplers: [2]Sampler,

    const Self = @This();

    pub fn startPixel(self: *Self, sample: u32, seed: u32) void {
        for (&self.samplers) |*s| {
            s.startPixel(sample, seed);
        }
    }

    pub fn li(self: *Self, ray: *Ray, worker: *Worker) Vec4f {
        var primary_ray = true;
        var treat_as_singular = true;
        var transparent = true;
        var from_subsurface = false;

        var throughput = @splat(4, @as(f32, 1.0));
        var old_throughput = @splat(4, @as(f32, 1.0));
        var result = @splat(4, @as(f32, 0.0));

        var isec = Intersection{};

        while (true) {
            const filter: ?Filter = if (ray.depth <= 1 or primary_ray) null else .Nearest;

            var sampler = self.pickSampler(ray.depth);

            if (!worker.nextEvent(ray, throughput, &isec, filter, sampler)) {
                break;
            }

            throughput *= isec.volume.tr;

            const wo = -ray.ray.direction;

            var pure_emissive: bool = undefined;
            const energy = isec.evaluateRadiance(
                ray.ray.origin,
                wo,
                filter,
                sampler,
                worker.scene,
                &pure_emissive,
            ) orelse @splat(4, @as(f32, 0.0));

            if (treat_as_singular or !Light.isLight(isec.lightId(worker.scene))) {
                result += throughput * energy;
            }

            if (pure_emissive) {
                transparent = transparent and !isec.visibleInCamera(worker.scene) and ray.ray.maxT() >= ro.Ray_max_t;
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

            const avoid_caustics = self.settings.avoid_caustics and (!primary_ray);

            const mat_sample = worker.sampleMaterial(
                ray.*,
                wo,
                isec,
                filter,
                sampler,
                0.0,
                avoid_caustics,
                from_subsurface,
            );

            if (worker.aov.active()) {
                worker.commonAOV(throughput, ray.*, isec, &mat_sample, primary_ray);
            }

            result += throughput * self.directLight(ray.*, isec, &mat_sample, filter, sampler, worker);

            const sample_result = mat_sample.sample(sampler);
            if (0.0 == sample_result.pdf or math.allLessEqualZero3(sample_result.reflection)) {
                break;
            }

            if (sample_result.class.specular) {
                if (avoid_caustics) {
                    break;
                }

                treat_as_singular = true;
            } else if (!sample_result.class.straight) {
                treat_as_singular = false;
                primary_ray = false;
            }

            if (!(sample_result.class.straight and sample_result.class.transmission)) {
                ray.depth += 1;
            }

            if (sample_result.class.straight) {
                ray.ray.setMinMaxT(ro.offsetF(ray.ray.maxT()), ro.Ray_max_t);
            } else {
                ray.ray.origin = isec.offsetP(sample_result.wi);
                ray.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                transparent = false;
                from_subsurface = false;
            }

            if (0.0 == ray.wavelength) {
                ray.wavelength = sample_result.wavelength;
            }

            old_throughput = throughput;
            throughput *= sample_result.reflection / @splat(4, sample_result.pdf);

            if (sample_result.class.transmission) {
                worker.interfaceChange(sample_result.wi, isec, filter, sampler);
            }

            from_subsurface = from_subsurface or isec.subsurface();

            sampler.incrementPadding();
        }

        for (&self.samplers) |*s| {
            s.incrementSample();
        }

        return hlp.composeAlpha(result, throughput, transparent);
    }

    fn directLight(
        self: *Self,
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

        var shadow_ray: Ray = undefined;
        shadow_ray.depth = ray.depth;
        shadow_ray.time = ray.time;
        shadow_ray.wavelength = ray.wavelength;

        const select = sampler.sample1D();
        const split = self.splitting(ray.depth);

        const lights = worker.randomLightSpatial(p, n, translucent, select, split);

        for (lights) |l| {
            const light = worker.scene.light(l.offset);
            const light_sample = light.sampleTo(
                p,
                n,
                ray.time,
                translucent,
                sampler,
                worker.scene,
            ) orelse continue;

            shadow_ray.ray.origin = p;
            shadow_ray.ray.setDirection(light_sample.wi, light_sample.offset());
            const tr = worker.visibility(&shadow_ray, isec, filter, sampler) orelse continue;

            const bxdf = mat_sample.evaluate(light_sample.wi);

            const radiance = light.evaluateTo(p, light_sample, filter, sampler, worker.scene);

            const weight = 1.0 / (l.pdf * light_sample.pdf());

            result += @splat(4, weight) * (tr * radiance * bxdf.reflection);
        }

        return result;
    }

    fn splitting(self: *const Self, bounce: u32) bool {
        return .Adaptive == self.settings.light_sampling and bounce < 3;
    }

    fn pickSampler(self: *Self, bounce: u32) *Sampler {
        if (bounce < 4) {
            return &self.samplers[0];
        }

        return &self.samplers[1];
    }
};

pub const Factory = struct {
    settings: PathtracerDL.Settings,

    pub fn create(self: Factory, rng: *RNG) PathtracerDL {
        return .{
            .settings = self.settings,
            .samplers = .{ .{ .Sobol = .{} }, .{ .Random = .{ .rng = rng } } },
        };
    }
};
