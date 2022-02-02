const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const Filter = @import("../../../image/texture/sampler.zig").Filter;
const scn = @import("../../../scene/constants.zig");
const ro = @import("../../../scene/ray_offset.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const AOV = struct {
    const Num_dedicated_samplers = 1;

    pub const Value = enum {
        AO,
        Tangent,
        Bitangent,
        GeometricNormal,
        ShadingNormal,
        Photons,
    };

    pub const Settings = struct {
        value: Value,

        num_samples: u32,
        max_bounces: u32,

        radius: f32,

        photons_not_only_through_specular: bool,
    };

    settings: Settings,

    samplers: [2]Sampler = [2]Sampler{ .{ .Sobol = .{} }, .{ .Random = .{} } },

    const Self = @This();

    pub fn startPixel(self: *Self, seed: u32) void {
        for (self.samplers) |*s| {
            s.startPixel(seed);
        }
    }

    pub fn li(
        self: *Self,
        ray: *Ray,
        isec: *Intersection,
        worker: *Worker,
        initial_stack: InterfaceStack,
    ) Vec4f {
        worker.super.resetInterfaceStack(initial_stack);

        return switch (self.settings.value) {
            .AO => self.ao(ray.*, isec.*, worker),
            .Tangent, .Bitangent, .GeometricNormal, .ShadingNormal => self.vector(ray.*, isec.*, worker),
            .Photons => self.photons(ray, isec, worker),
        };
    }

    fn ao(self: *Self, ray: Ray, isec: Intersection, worker: *Worker) Vec4f {
        const num_samples_reciprocal = 1.0 / @intToFloat(f32, self.settings.num_samples);

        var result: f32 = 0.0;

        const wo = -ray.ray.direction;
        const mat_sample = isec.sample(wo, ray, null, false, &worker.super);

        var occlusion_ray: Ray = undefined;

        occlusion_ray.ray.origin = isec.offsetPN(mat_sample.super().geometricNormal(), false);
        occlusion_ray.ray.setMaxT(self.settings.radius);
        occlusion_ray.time = ray.time;

        var sampler = self.samplers[0];

        var i = self.settings.num_samples;
        while (i > 0) : (i -= 1) {
            const sample = sampler.sample2D(&worker.super.rng);

            const t = mat_sample.super().shadingTangent();
            const b = mat_sample.super().shadingBitangent();
            const n = mat_sample.super().shadingNormal();

            const ws = math.smpl.orientedHemisphereCosine(sample, t, b, n);

            occlusion_ray.ray.setDirection(ws);

            if (worker.super.visibility(occlusion_ray, null)) |_| {
                result += num_samples_reciprocal;
            }

            sampler.incrementSample();
        }

        return .{ result, result, result, 1.0 };
    }

    fn vector(self: Self, ray: Ray, isec: Intersection, worker: *Worker) Vec4f {
        const wo = -ray.ray.direction;
        const mat_sample = isec.sample(wo, ray, null, false, &worker.super);

        var vec: Vec4f = undefined;

        switch (self.settings.value) {
            .Tangent => vec = isec.geo.t,
            .Bitangent => vec = isec.geo.b,
            .GeometricNormal => vec = isec.geo.geo_n,
            .ShadingNormal => {
                if (!mat_sample.super().sameHemisphere(wo)) {
                    return .{ 0.0, 0.0, 0.0, 1.0 };
                }

                vec = mat_sample.super().shadingNormal();
            },
            else => return .{ 0.0, 0.0, 0.0, 1.0 },
        }

        vec = Vec4f{ vec[0], vec[1], vec[2], 1.0 };

        return math.clamp(@splat(4, @as(f32, 0.5)) * (vec + @splat(4, @as(f32, 1.0))), 0.0, 1.0);
    }

    fn photons(self: *Self, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        var primary_ray = true;
        var direct = true;
        var from_subsurface = false;

        var throughput = @splat(4, @as(f32, 1.0));
        var wo1 = @splat(4, @as(f32, 0.0));

        var i: u32 = 0;
        while (true) : (i += 1) {
            const wo = -ray.ray.direction;

            const filter: ?Filter = if (ray.depth <= 1 or primary_ray) null else .Nearest;

            const mat_sample = worker.super.sampleMaterial(
                ray.*,
                wo,
                wo1,
                isec.*,
                filter,
                0.0,
                true,
                from_subsurface,
            );

            wo1 = wo;

            if (mat_sample.isPureEmissive()) {
                break;
            }

            var sampler = self.pickSampler(ray.depth);

            const sample_result = mat_sample.sample(sampler, &worker.super.rng);
            if (0.0 == sample_result.pdf) {
                break;
            }

            if (sample_result.typef.is(.Specular)) {} else if (sample_result.typef.no2(.Straight, .Transmission)) {
                if (primary_ray) {
                    primary_ray = false;

                    const indirect = !direct and 0 != ray.depth;
                    if (self.settings.photons_not_only_through_specular or indirect) {
                        worker.addPhoton(throughput * worker.photonLi(isec.*, mat_sample));
                        break;
                    }
                }
            }

            if (!sample_result.typef.equals(.StraightTransmission)) {
                ray.depth += 1;
            }

            if (ray.depth >= self.settings.max_bounces) {
                break;
            }

            if (sample_result.typef.is(.Straight)) {
                ray.ray.setMinT(ro.offsetF(ray.ray.maxT()));
            } else {
                ray.ray.origin = isec.offsetP(sample_result.wi);
                ray.ray.setDirection(sample_result.wi);

                direct = false;
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

                throughput *= vr.tr;

                if (.Abort == vr.event) {
                    break;
                }
            } else if (!worker.super.intersectAndResolveMask(ray, filter, isec)) {
                break;
            }

            sampler.incrementPadding();
        }

        for (self.samplers) |*s| {
            s.incrementSample();
        }

        return @splat(4, @as(f32, 0.0));
    }

    fn pickSampler(self: *Self, bounce: u32) *Sampler {
        if (bounce < 4) {
            return &self.samplers[0];
        }

        return &self.samplers[1];
    }
};

pub const Factory = struct {
    settings: AOV.Settings,

    pub fn create(self: Factory) AOV {
        return .{ .settings = self.settings };
    }
};
