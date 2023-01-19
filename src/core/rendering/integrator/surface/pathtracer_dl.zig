const Ray = @import("../../../scene/ray.zig").Ray;
const Vertex = @import("../../../scene/vertex.zig").Vertex;
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
    const Num_dedicated_samplers = 3;

    pub const Settings = struct {
        num_samples: u32,
        min_bounces: u32,
        max_bounces: u32,

        light_sampling: hlp.LightSampling,

        avoid_caustics: bool,
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

    pub fn li(self: *Self, ray: *Ray, isec: *Intersection, worker: *Worker, initial_stack: *const InterfaceStack) Vec4f {
        const num_samples_reciprocal = 1.0 / @intToFloat(f32, self.settings.num_samples);

        var result = @splat(4, @as(f32, 0.0));

        var i = self.settings.num_samples;
        while (i > 0) : (i -= 1) {
            result += @splat(4, num_samples_reciprocal) * self.integrate(ray.*, isec.*, initial_stack, worker);

            for (self.samplers) |*s| {
                s.incrementSample();
            }
        }

        return result;
    }

    fn integrate(
        self: *Self,
        ray: Ray,
        isec: Intersection,
        initial_stack: *const InterfaceStack,
        worker: *Worker,
    ) Vec4f {
        var primary_ray = true;
        var treat_as_singular = true;
        var transparent = true;
        var from_subsurface = false;

        var throughput = @splat(4, @as(f32, 1.0));
        var result = @splat(4, @as(f32, 0.0));

        var vertex: Vertex = undefined;
        vertex.start(ray, isec, initial_stack);

        var i: u32 = 0;
        while (true) : (i += 1) {
            const wo = -vertex.ray.ray.direction;

            const filter: ?Filter = if (vertex.ray.depth <= 1 or primary_ray) null else .Nearest;
            const avoid_caustics = self.settings.avoid_caustics and (!primary_ray);

            var pure_emissive: bool = undefined;
            const energy = isec.evaluateRadiance(
                vertex.ray.ray.origin,
                wo,
                filter,
                worker.scene,
                &pure_emissive,
            ) orelse @splat(4, @as(f32, 0.0));

            if (treat_as_singular or !Light.isLight(isec.lightId(worker.scene))) {
                result += throughput * energy;
            }

            if (pure_emissive) {
                transparent = transparent and !vertex.isec.visibleInCamera(worker.scene) and ray.ray.maxT() >= ro.Ray_max_t;
                break;
            }

            const mat_sample = worker.sampleMaterial(
                &vertex,
                wo,
                filter,
                0.0,
                avoid_caustics,
                from_subsurface,
            );

            if (worker.aov.active()) {
                worker.commonAOV(throughput, vertex.ray, vertex.isec, &mat_sample, primary_ray);
            }

            vertex.wo1 = wo;

            var sampler = self.pickSampler(ray.depth);

            result += throughput * self.directLight(&vertex, &mat_sample, filter, sampler, worker);

            const sample_result = mat_sample.sample(sampler, false, &worker.bxdfs)[0];
            if (0.0 == sample_result.pdf) {
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
                vertex.ray.depth += 1;
            }

            if (sample_result.class.straight) {
                vertex.ray.ray.setMinMaxT(ro.offsetF(vertex.ray.ray.maxT()), ro.Ray_max_t);
            } else {
                vertex.ray.ray.origin = vertex.isec.offsetP(sample_result.wi);
                vertex.ray.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                transparent = false;
                from_subsurface = false;
            }

            if (0.0 == ray.wavelength) {
                vertex.ray.wavelength = sample_result.wavelength;
            }

            throughput *= sample_result.reflection / @splat(4, sample_result.pdf);

            if (sample_result.class.transmission) {
                vertex.interfaceChange(sample_result.wi, vertex.isec, worker.scene);
            }

            from_subsurface = from_subsurface or isec.subsurface;

            if (!vertex.interface_stack.empty()) {
                const vr = worker.volume(&vertex, filter, sampler);

                if (.Absorb == vr.event) {
                    if (0 == vertex.ray.depth) {
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
            } else if (!worker.intersectAndResolveMask(&vertex.ray, filter, &vertex.isec)) {
                break;
            }

            if (vertex.ray.depth >= self.settings.max_bounces) {
                break;
            }

            if (vertex.ray.depth >= self.settings.min_bounces) {
                if (hlp.russianRoulette(&throughput, sampler.sample1D())) {
                    break;
                }
            }

            sampler.incrementPadding();
        }

        return hlp.composeAlpha(result, throughput, transparent);
    }

    fn directLight(
        self: *Self,
        vertex: *const Vertex,
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
        const p = vertex.isec.offsetPN(n, translucent);

        var shadow_ray: Ray = undefined;
        shadow_ray.ray.origin = p;
        shadow_ray.depth = vertex.ray.depth;
        shadow_ray.time = vertex.ray.time;
        shadow_ray.wavelength = vertex.ray.wavelength;

        const select = sampler.sample1D();
        const split = self.splitting(vertex.ray.depth);

        const lights = worker.randomLightSpatial(p, n, translucent, select, split);

        for (lights) |l| {
            const light = worker.scene.light(l.offset);
            const light_sample = light.sampleTo(
                p,
                n,
                vertex.ray.time,
                translucent,
                sampler,
                worker.scene,
            ) orelse continue;

            shadow_ray.ray.setDirection(light_sample.wi, light_sample.offset());
            const tr = worker.transmitted(shadow_ray, vertex, mat_sample.super().wo, filter) orelse continue;

            const bxdf = mat_sample.evaluate(light_sample.wi);

            const radiance = light.evaluateTo(p, light_sample, filter, worker.scene);

            const weight = 1.0 / (l.pdf * light_sample.pdf());

            result += @splat(4, weight) * (tr * radiance * bxdf.reflection);
        }

        return result;
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
    settings: PathtracerDL.Settings,

    pub fn create(self: Factory, rng: *RNG) PathtracerDL {
        return .{
            .settings = self.settings,
            .samplers = .{ .{ .Sobol = .{} }, .{ .Random = .{ .rng = rng } } },
        };
    }
};
