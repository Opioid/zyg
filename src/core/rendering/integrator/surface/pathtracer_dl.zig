const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const Filter = @import("../../../image/texture/sampler.zig").Filter;
const Max_lights = @import("../../../scene/light/tree.zig").Tree.Max_lights;
const hlp = @import("../helper.zig");
const mat = @import("../../../scene/material/material.zig");
const scn = @import("../../../scene/constants.zig");
const ro = @import("../../../scene/ray_offset.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PathtracerDL = struct {
    const Num_dedicated_samplers = 3;

    pub const Settings = struct {
        num_samples: u32,
        min_bounces: u32,
        max_bounces: u32,

        light_sampling: hlp.LightSampling,

        avoid_caustics: bool,
    };

    settings: Settings,

    sampler: Sampler = .{ .Sobol = .{} },

    const Self = @This();

    pub fn startPixel(self: *Self, sample: u32, seed: u32) void {
        self.sampler.startPixel(sample, seed);
    }

    pub fn li(
        self: *Self,
        ray: *Ray,
        isec: *Intersection,
        worker: *Worker,
        initial_stack: InterfaceStack,
    ) Vec4f {
        const num_samples_reciprocal = 1.0 / @intToFloat(f32, self.settings.num_samples);

        var result = @splat(4, @as(f32, 0.0));

        var i = self.settings.num_samples;
        while (i > 0) : (i -= 1) {
            worker.super.resetInterfaceStack(initial_stack);

            var split_ray = ray.*;
            var split_isec = isec.*;

            result += @splat(4, num_samples_reciprocal) * self.integrate(&split_ray, &split_isec, worker);

            self.sampler.incrementSample();
        }

        return result;
    }

    fn integrate(self: *Self, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        var primary_ray = true;
        var treat_as_singular = true;
        var transparent = true;
        var from_subsurface = false;

        var throughput = @splat(4, @as(f32, 1.0));
        var result = @splat(4, @as(f32, 0.0));
        var wo1 = @splat(4, @as(f32, 0.0));

        var i: u32 = 0;
        while (true) : (i += 1) {
            const wo = -ray.ray.direction;

            const filter: ?Filter = if (ray.depth <= 1 or primary_ray) null else .Nearest;
            const avoid_caustics = self.settings.avoid_caustics and (!primary_ray);

            const mat_sample = worker.super.sampleMaterial(
                ray.*,
                wo,
                wo1,
                isec.*,
                filter,
                0.0,
                avoid_caustics,
                from_subsurface,
            );

            wo1 = wo;

            if (mat_sample.super().sameHemisphere(wo)) {
                if (treat_as_singular) {
                    result += throughput * mat_sample.super().radiance;
                }
            }

            if (mat_sample.isPureEmissive()) {
                transparent = transparent and !isec.visibleInCamera(worker.super) and ray.ray.maxT() >= scn.Ray_max_t;
                break;
            }

            result += throughput * self.directLight(ray.*, isec.*, mat_sample, filter, worker);

            const sample_result = mat_sample.sample(&self.sampler, &worker.super.rng);
            if (0.0 == sample_result.pdf) {
                break;
            }

            if (sample_result.typef.is(.Specular)) {
                if (avoid_caustics) {
                    break;
                }

                treat_as_singular = true;
            } else if (sample_result.typef.no(.Straight)) {
                treat_as_singular = false;
                primary_ray = false;
            }

            if (!sample_result.typef.equals(.StraightTransmission)) {
                ray.depth += 1;
            }

            if (sample_result.typef.is(.Straight)) {
                ray.ray.setMinT(ro.offsetF(ray.ray.maxT()));
            } else {
                ray.ray.origin = isec.offsetP(sample_result.wi);
                ray.ray.setDirection(sample_result.wi);

                transparent = false;
                from_subsurface = false;
            }

            ray.ray.setMaxT(scn.Ray_max_t);

            if (0.0 == ray.wavelength) {
                ray.wavelength = sample_result.wavelength;
            }

            throughput *= sample_result.reflection / @splat(4, sample_result.pdf);

            if (sample_result.typef.is(.Transmission)) {
                worker.super.interfaceChange(sample_result.wi, isec.*);
            }

            from_subsurface = from_subsurface or isec.subsurface;

            if (!worker.super.interface_stack.empty()) {
                const vr = worker.volume(ray, isec, filter);

                if (.Absorb == vr.event) {
                    if (0 == ray.depth) {
                        // This is the direct eye-light connection for the volume case.
                        result += vr.li;
                    }

                    break;
                }

                // This is only needed for Tracking_single at the moment...
                result += throughput * vr.li;
                throughput *= vr.tr;

                if (.Abort == vr.event) {
                    break;
                }
            } else if (!worker.super.intersectAndResolveMask(ray, filter, isec)) {
                break;
            }

            if (ray.depth >= self.settings.max_bounces) {
                break;
            }

            if (ray.depth >= self.settings.min_bounces) {
                if (hlp.russianRoulette(&throughput, self.sampler.sample1D(&worker.super.rng))) {
                    break;
                }
            }

            self.sampler.incrementBounce();
        }

        return hlp.composeAlpha(result, throughput, transparent);
    }

    fn directLight(
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

        var shadow_ray: Ray = undefined;
        shadow_ray.ray.origin = p;
        shadow_ray.depth = ray.depth;
        shadow_ray.time = ray.time;
        shadow_ray.wavelength = ray.wavelength;

        const select = self.sampler.sample1D(&worker.super.rng);
        const split = self.splitting(ray.depth);

        const lights = worker.super.scene.randomLightSpatial(p, n, translucent, select, split, &worker.super.lights);

        for (lights) |l| {
            const light = worker.super.scene.light(l.offset);
            const light_sample = light.sampleTo(
                p,
                n,
                ray.time,
                translucent,
                &self.sampler,
                &worker.super,
            ) orelse continue;

            shadow_ray.ray.setDirection(light_sample.wi);
            shadow_ray.ray.setMaxT(light_sample.t());
            const tr = worker.transmitted(&shadow_ray, mat_sample.super().wo, isec, filter) orelse continue;

            const bxdf = mat_sample.evaluate(light_sample.wi);

            const radiance = light.evaluateTo(light_sample, .Nearest, worker.super);

            const weight = 1.0 / (l.pdf * light_sample.pdf());

            result += @splat(4, weight) * (tr * radiance * bxdf.reflection);
        }

        return result;
    }

    fn splitting(self: Self, bounce: u32) bool {
        return .Adaptive == self.settings.light_sampling and
            bounce < Num_dedicated_samplers;
    }
};

pub const Factory = struct {
    settings: PathtracerDL.Settings,

    pub fn create(self: Factory) PathtracerDL {
        return .{ .settings = self.settings };
    }
};
