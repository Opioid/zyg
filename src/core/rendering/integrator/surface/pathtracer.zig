const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const hlp = @import("../helper.zig");
const ro = @import("../../../scene/ray_offset.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Pathtracer = struct {
    pub const Settings = struct {
        min_bounces: u32,
        max_bounces: u32,
        avoid_caustics: bool,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: *Self, ray: *Ray, worker: *Worker) Vec4f {
        var primary_ray = true;
        var transparent = true;
        var from_subsurface = false;

        var throughput = @splat(4, @as(f32, 1.0));
        var old_throughput = @splat(4, @as(f32, 1.0));
        var result = @splat(4, @as(f32, 0.0));

        var isec = Intersection{};

        while (true) {
            var sampler = worker.pickSampler(ray.depth);

            if (!worker.nextEvent(ray, throughput, &isec, sampler)) {
                break;
            }

            throughput *= isec.volume.tr;

            const wo = -ray.ray.direction;

            var pure_emissive: bool = undefined;
            const energy = isec.evaluateRadiance(
                ray.ray.origin,
                wo,
                sampler,
                worker.scene,
                &pure_emissive,
            ) orelse @splat(4, @as(f32, 0.0));

            result += throughput * energy;

            if (pure_emissive) {
                transparent = transparent and !isec.visibleInCamera(worker.scene) and ray.ray.maxT() >= ro.Ray_max_t;
                break;
            }

            const avoid_caustics = self.settings.avoid_caustics and (!primary_ray);
            const mat_sample = worker.sampleMaterial(
                ray.*,
                wo,
                isec,
                sampler,
                0.0,
                if (avoid_caustics) .Avoid else .Full,
                from_subsurface,
            );

            if (worker.aov.active()) {
                worker.commonAOV(throughput, ray.*, isec, &mat_sample, primary_ray);
            }

            if (ray.depth >= self.settings.max_bounces) {
                break;
            }

            if (ray.depth >= self.settings.min_bounces) {
                if (hlp.russianRoulette(&throughput, old_throughput, sampler.sample1D())) {
                    break;
                }
            }

            const sample_result = mat_sample.sample(sampler);
            if (0.0 == sample_result.pdf or math.allLessEqualZero3(sample_result.reflection)) {
                break;
            }

            if (sample_result.class.specular) {
                if (avoid_caustics) {
                    break;
                }
            } else if (!sample_result.class.straight) {
                primary_ray = false;
            }

            old_throughput = throughput;
            throughput *= sample_result.reflection / @splat(4, sample_result.pdf);

            if (!(sample_result.class.straight and sample_result.class.transmission)) {
                ray.depth += 1;
            }

            if (sample_result.class.straight) {
                ray.ray.setMinMaxT(isec.offsetT(ray.ray.maxT()), ro.Ray_max_t);
            } else {
                ray.ray.origin = isec.offsetP(sample_result.wi);
                ray.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                transparent = false;
                from_subsurface = false;
            }

            if (0.0 == ray.wavelength) {
                ray.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                worker.interfaceChange(sample_result.wi, isec, sampler);
            }

            from_subsurface = from_subsurface or isec.subsurface();

            sampler.incrementPadding();
        }

        return hlp.composeAlpha(result, throughput, transparent);
    }
};

pub const Factory = struct {
    settings: Pathtracer.Settings,

    pub fn create(self: Factory) Pathtracer {
        return .{ .settings = self.settings };
    }
};
