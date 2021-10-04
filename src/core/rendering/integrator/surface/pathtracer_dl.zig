const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const Filter = @import("../../../image/texture/sampler.zig").Filter;
const mat = @import("../../../scene/material/material.zig");
const scn = @import("../../../scene/constants.zig");
const ro = @import("../../../scene/ray_offset.zig");
const smp = @import("../../../sampler/sampler.zig");
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
    };

    settings: Settings,

    samplers: [2 * Num_dedicated_samplers + 1]smp.Sampler,

    const Self = @This();

    pub fn init(alloc: *Allocator, settings: Settings, max_samples_per_pixel: u32) !Self {
        const total_samples_per_pixel = settings.num_samples * max_samples_per_pixel;

        const Max_lights = 4;

        return Self{
            .settings = settings,
            .samplers = .{
                .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, 1, 1, total_samples_per_pixel) },
                .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, Max_lights + 1, Max_lights, total_samples_per_pixel) },
                .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, 1, 1, total_samples_per_pixel) },
                .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, Max_lights + 1, Max_lights, total_samples_per_pixel) },
                .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, 1, 1, total_samples_per_pixel) },
                .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, Max_lights + 1, Max_lights, total_samples_per_pixel) },
                .{ .Random = .{} },
            },
        };
    }

    pub fn deinit(self: *Self, alloc: *Allocator) void {
        for (self.samplers) |*s| {
            s.deinit(alloc);
        }
    }

    pub fn startPixel(self: *Self) void {
        for (self.samplers) |*s| {
            s.startPixel();
        }
    }

    pub fn li(self: *Self, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        const num_samples_reciprocal = 1.0 / @intToFloat(f32, self.settings.num_samples);

        var result = @splat(4, @as(f32, 0.0));

        var i = self.settings.num_samples;
        while (i > 0) : (i -= 1) {
            var split_ray = ray.*;
            var split_isec = isec.*;

            result += @splat(4, num_samples_reciprocal) * self.integrate(&split_ray, &split_isec, worker);
        }

        return result;
    }

    fn integrate(self: *Self, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        var primary_ray: bool = true;
        var treat_as_singular: bool = true;

        var throughput = @splat(4, @as(f32, 1.0));
        var result = @splat(4, @as(f32, 0.0));

        var i: u32 = 0;
        while (true) : (i += 1) {
            const wo = -ray.ray.direction;

            const filter: ?Filter = if (ray.depth <= 1 or primary_ray) null else .Nearest;

            const mat_sample = isec.sample(wo, ray.*, filter, &worker.super);

            if (mat_sample.super().sameHemisphere(wo)) {
                if (treat_as_singular) {
                    result += throughput * mat_sample.super().radiance;
                }
            }

            if (mat_sample.isPureEmissive()) {
                break;
            }

            if (ray.depth >= self.settings.max_bounces) {
                break;
            }

            result += throughput * self.directLight(ray.*, isec.*, mat_sample, filter, worker);

            const sample_result = mat_sample.sample(self.materialSampler(ray.depth), &worker.super.rng);
            if (0.0 == sample_result.pdf) {
                break;
            }

            if (sample_result.typef.is(.Specular)) {
                treat_as_singular = true;
            } else if (sample_result.typef.no(.Straight)) {
                treat_as_singular = false;
                primary_ray = false;
            }

            if (!sample_result.typef.equals(.Straight_transmission)) {
                ray.depth += 1;
            }

            if (sample_result.typef.is(.Straight)) {
                ray.ray.setMinT(ro.offsetF(ray.ray.maxT()));
            } else {
                ray.ray.origin = isec.offsetP(sample_result.wi);
                ray.ray.setDirection(sample_result.wi);
            }

            ray.ray.setMaxT(scn.Ray_max_t);

            throughput *= sample_result.reflection / @splat(4, sample_result.pdf);

            if (!worker.super.intersectAndResolveMask(ray, filter, isec)) {
                break;
            }
        }

        return result;
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

        _ = filter;

        const translucent = mat_sample.isTranslucent();

        const n = mat_sample.super().geometricNormal();
        const p = isec.offsetPN(n, translucent);

        var shadow_ray: Ray = undefined;
        shadow_ray.ray.origin = p;
        shadow_ray.depth = ray.depth;
        shadow_ray.time = ray.time;

        var sampler = self.lightSampler(ray.depth);

        const select = sampler.sample1D(&worker.super.rng, worker.super.lights.len);
        const split: bool = false;

        const lights = worker.super.scene.randomLight(p, n, translucent, select, split, &worker.super.lights);

        for (lights) |l, i| {
            const light = worker.super.scene.light(l.offset);

            const light_sample = light.sampleTo(p, n, translucent, sampler, i, &worker.super) orelse continue;

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
};

pub const Factory = struct {
    settings: PathtracerDL.Settings = .{ .num_samples = 1, .radius = 1.0 },

    pub fn create(self: Factory, alloc: *Allocator, max_samples_per_pixel: u32) !PathtracerDL {
        return try PathtracerDL.init(alloc, self.settings, max_samples_per_pixel);
    }
};
