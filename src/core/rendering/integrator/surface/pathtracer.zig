const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const Filter = @import("../../../image/texture/texture_sampler.zig").Filter;
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

    samplers: [2]Sampler,

    const Self = @This();

    pub fn startPixel(self: *Self, sample: u32, seed: u32) void {
        for (&self.samplers) |*s| {
            s.startPixel(sample, seed);
        }
    }

    pub fn li(self: *Self, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        var primary_ray = true;
        var transparent = true;
        var from_subsurface = false;

        var throughput = @splat(4, @as(f32, 1.0));
        var old_throughput = @splat(4, @as(f32, 1.0));
        var result = @splat(4, @as(f32, 0.0));

        var i: u32 = 0;
        while (true) : (i += 1) {
            const wo = -ray.ray.direction;

            const filter: ?Filter = if (ray.depth <= 1 or primary_ray) null else .Nearest;
            const avoid_caustics = self.settings.avoid_caustics and (!primary_ray);

            var pure_emissive: bool = undefined;
            const energy = isec.evaluateRadiance(
                ray.ray.origin,
                wo,
                filter,
                worker.scene,
                &pure_emissive,
            ) orelse @splat(4, @as(f32, 0.0));

            result += throughput * energy;

            if (pure_emissive) {
                transparent = transparent and !isec.visibleInCamera(worker.scene) and ray.ray.maxT() >= ro.Ray_max_t;
                break;
            }

            const mat_sample = worker.sampleMaterial(
                ray.*,
                wo,
                isec.*,
                filter,
                0.0,
                avoid_caustics,
                from_subsurface,
            );

            if (worker.aov.active()) {
                worker.commonAOV(throughput, ray.*, isec.*, &mat_sample, primary_ray);
            }

            if (ray.depth >= self.settings.max_bounces) {
                break;
            }

            var sampler = self.pickSampler(ray.depth);

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
                worker.interfaceChange(sample_result.wi, isec, filter);
            }

            from_subsurface = from_subsurface or isec.subsurface();

            if (!worker.nextEvent(ray, throughput, isec, filter, sampler)) {
                break;
            }

            throughput *= isec.volume.tr;

            sampler.incrementPadding();
        }

        for (&self.samplers) |*s| {
            s.incrementSample();
        }

        return hlp.composeAlpha(result, throughput, transparent);
    }

    fn pickSampler(self: *Self, bounce: u32) *Sampler {
        if (bounce < 4) {
            return &self.samplers[0];
        }

        return &self.samplers[1];
    }
};

pub const Factory = struct {
    settings: Pathtracer.Settings,

    pub fn create(self: Factory, rng: *RNG) Pathtracer {
        return .{
            .settings = self.settings,
            .samplers = .{ .{ .Sobol = .{} }, .{ .Random = .{ .rng = rng } } },
        };
    }
};
