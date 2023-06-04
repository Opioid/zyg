const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const ro = @import("../../../scene/ray_offset.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const AOV = struct {
    pub const Value = enum {
        AO,
        Tangent,
        Bitangent,
        GeometricNormal,
        ShadingNormal,
        LightSampleCount,
        Side,
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

    const Self = @This();

    pub fn li(self: *Self, ray: *Ray, worker: *Worker) Vec4f {
        var isec = Intersection{};
        var sampler = worker.pickSampler(0);

        if (!worker.nextEvent(ray, @splat(4, @as(f32, 1.0)), &isec, sampler)) {
            return @splat(4, @as(f32, 0.0));
        }

        const result = switch (self.settings.value) {
            .AO => self.ao(ray.*, isec, worker),
            .Tangent, .Bitangent, .GeometricNormal, .ShadingNormal => self.vector(ray.*, isec, worker),
            .LightSampleCount => self.lightSampleCount(ray.*, isec, worker),
            .Side => self.side(ray.*, isec, worker),
            .Photons => self.photons(ray, &isec, worker),
        };

        return isec.volume.tr * result;
    }

    fn ao(self: *Self, ray: Ray, isec: Intersection, worker: *Worker) Vec4f {
        const num_samples_reciprocal = 1.0 / @intToFloat(f32, self.settings.num_samples);
        const radius = self.settings.radius;

        var result: f32 = 0.0;
        var sampler = worker.pickSampler(0);

        const wo = -ray.ray.direction;

        const mat_sample = isec.sample(wo, ray, sampler, false, worker);

        var occlusion_ray: Ray = undefined;

        const origin = isec.offsetPN(mat_sample.super().geometricNormal(), false);

        occlusion_ray.time = ray.time;

        var i = self.settings.num_samples;
        while (i > 0) : (i -= 1) {
            const sample = sampler.sample2D();

            const t = mat_sample.super().shadingTangent();
            const b = mat_sample.super().shadingBitangent();
            const n = mat_sample.super().shadingNormal();

            const ws = math.smpl.orientedHemisphereCosine(sample, t, b, n);

            occlusion_ray.ray.origin = origin;
            occlusion_ray.ray.setDirection(ws, radius);

            if (worker.scene.visibility(occlusion_ray, sampler, worker)) |_| {
                result += num_samples_reciprocal;
            }

            sampler.incrementSample();
        }

        return .{ result, result, result, 1.0 };
    }

    fn vector(self: *Self, ray: Ray, isec: Intersection, worker: *Worker) Vec4f {
        var sampler = worker.pickSampler(0);

        const wo = -ray.ray.direction;
        const mat_sample = isec.sample(wo, ray, sampler, false, worker);

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

    fn lightSampleCount(self: *Self, ray: Ray, isec: Intersection, worker: *Worker) Vec4f {
        _ = self;

        var sampler = worker.pickSampler(0);

        const wo = -ray.ray.direction;

        const mat_sample = isec.sample(wo, ray, sampler, false, worker);

        const n = mat_sample.super().geometricNormal();
        const p = isec.offsetPN(n, false);

        const lights = worker.randomLightSpatial(p, n, false, sampler.sample1D(), true);

        const r = @intToFloat(f32, lights.len) / @intToFloat(f32, worker.lights.len);

        return .{ r, r, r, 1.0 };
    }

    fn side(self: *Self, ray: Ray, isec: Intersection, worker: *Worker) Vec4f {
        _ = self;

        var sampler = worker.pickSampler(0);

        const wo = -ray.ray.direction;
        const mat_sample = isec.sample(wo, ray, sampler, false, worker);

        const super = mat_sample.super();
        const n = math.cross3(super.shadingTangent(), super.shadingBitangent());
        const same_side = math.dot3(n, super.shadingNormal()) > 0.0;
        return if (same_side) Vec4f{ 0.2, 1.0, 0.1, 0.0 } else Vec4f{ 1.0, 0.1, 0.2, 0.0 };
    }

    fn photons(self: *Self, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        var primary_ray = true;
        var direct = true;
        var from_subsurface = false;

        var throughput = @splat(4, @as(f32, 1.0));

        var i: u32 = 0;
        while (true) : (i += 1) {
            const wo = -ray.ray.direction;

            var sampler = worker.pickSampler(ray.depth);

            const mat_sample = worker.sampleMaterial(
                ray.*,
                wo,
                isec.*,
                sampler,
                0.0,
                true,
                from_subsurface,
            );

            if (mat_sample.isPureEmissive()) {
                break;
            }

            const sample_result = mat_sample.sample(sampler);
            if (0.0 == sample_result.pdf) {
                break;
            }

            if (sample_result.class.specular) {} else if (!sample_result.class.straight and !sample_result.class.transmission) {
                if (primary_ray) {
                    primary_ray = false;

                    const indirect = !direct and 0 != ray.depth;
                    if (self.settings.photons_not_only_through_specular or indirect) {
                        worker.addPhoton(throughput * worker.photonLi(isec.*, &mat_sample, sampler));
                        break;
                    }
                }
            }

            if (!(sample_result.class.straight and sample_result.class.transmission)) {
                ray.depth += 1;
            }

            if (ray.depth >= self.settings.max_bounces) {
                break;
            }

            if (sample_result.class.straight) {
                ray.ray.setMinMaxT(ro.offsetF(ray.ray.maxT()), ro.Ray_max_t);
            } else {
                ray.ray.origin = isec.offsetP(sample_result.wi);
                ray.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                direct = false;
                from_subsurface = false;
            }

            if (0.0 == ray.wavelength) {
                ray.wavelength = sample_result.wavelength;
            }

            throughput *= sample_result.reflection / @splat(4, sample_result.pdf);

            if (sample_result.class.transmission) {
                worker.interfaceChange(sample_result.wi, isec.*, sampler);
            }

            from_subsurface = from_subsurface or isec.subsurface();

            if (!worker.nextEvent(ray, throughput, isec, sampler)) {
                break;
            }

            throughput *= isec.volume.tr;

            sampler.incrementPadding();
        }

        return @splat(4, @as(f32, 0.0));
    }
};

pub const Factory = struct {
    settings: AOV.Settings,

    pub fn create(self: Factory) AOV {
        return .{ .settings = self.settings };
    }
};
