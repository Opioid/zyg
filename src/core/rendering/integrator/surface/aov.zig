const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const smp = @import("../../../sampler/sampler.zig");
const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const AOV = struct {
    pub const Value = enum {
        AO,
        Tangent,
        Bitangent,
        GeometricNormal,
        ShadingNormal,
    };

    pub const Settings = struct {
        value: Value,
        num_samples: u32,
        radius: f32,
    };

    settings: Settings,

    sampler: smp.Sampler,

    const Self = @This();

    pub fn init(alloc: Allocator, settings: Settings, max_samples_per_pixel: u32) !Self {
        const total_samples_per_pixel = settings.num_samples * max_samples_per_pixel;

        return Self{
            .settings = settings,
            .sampler = .{
                .GoldenRatio = try smp.GoldenRatio.init(alloc, 0, 1, total_samples_per_pixel),
            },
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.sampler.deinit(alloc);
    }

    pub fn startPixel(self: *Self) void {
        self.sampler.startPixel();
    }

    pub fn li(self: *Self, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        return switch (self.settings.value) {
            .AO => self.ao(ray, isec, worker),
            .Tangent, .Bitangent, .GeometricNormal, .ShadingNormal => self.vector(ray, isec, worker),
        };
    }

    fn ao(self: *Self, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        const num_samples_reciprocal = 1.0 / @intToFloat(f32, self.settings.num_samples);

        var result: f32 = 0.0;

        const wo = -ray.ray.direction;
        const mat_sample = isec.sample(wo, ray.*, null, false, &worker.super);

        var occlusion_ray: Ray = undefined;

        occlusion_ray.ray.origin = isec.offsetPN(mat_sample.super().geometricNormal(), false);
        occlusion_ray.ray.setMaxT(self.settings.radius);
        occlusion_ray.time = ray.time;

        var i = self.settings.num_samples;
        while (i > 0) : (i -= 1) {
            const sample = self.sampler.sample2D(&worker.super.rng, 0);

            const t = mat_sample.super().shadingTangent();
            const b = mat_sample.super().shadingBitangent();
            const n = mat_sample.super().shadingNormal();

            const ws = math.smpl.orientedHemisphereCosine(sample, t, b, n);

            occlusion_ray.ray.setDirection(ws);

            if (worker.super.visibility(occlusion_ray, null)) |_| {
                result += num_samples_reciprocal;
            }
        }

        return .{ result, result, result, 1.0 };
    }

    fn vector(self: *Self, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        const wo = -ray.ray.direction;
        const mat_sample = isec.sample(wo, ray.*, null, false, &worker.super);

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
};

pub const Factory = struct {
    settings: AOV.Settings,

    pub fn create(self: Factory, alloc: Allocator, max_samples_per_pixel: u32) !AOV {
        return try AOV.init(alloc, self.settings, max_samples_per_pixel);
    }
};
