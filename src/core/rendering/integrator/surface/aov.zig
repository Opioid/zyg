const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Probe = Vertex.Probe;
const Scene = @import("../../../scene/scene.zig").Scene;
const Worker = @import("../../worker.zig").Worker;
const bxdf = @import("../../../scene/material/bxdf.zig");
const Intersection = @import("../../../scene/shape/intersection.zig").Intersection;
const ro = @import("../../../scene/ray_offset.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");

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

    pub fn li(self: *const Self, input: *const Vertex, worker: *Worker) Vec4f {
        var vertex = input.*;

        const sampler = worker.pickSampler(0);

        var isec: Intersection = undefined;
        if (!worker.nextEvent(false, &vertex, &isec, sampler)) {
            return @splat(0.0);
        }

        const result = switch (self.settings.value) {
            .AO => self.ao(&vertex, &isec, worker),
            .Tangent, .Bitangent, .GeometricNormal, .ShadingNormal => self.vector(&vertex, &isec, worker),
            .LightSampleCount => self.lightSampleCount(&vertex, &isec, worker),
            .Side => self.side(&vertex, &isec, worker),
            .Photons => self.photons(&vertex, &isec, worker),
        };

        return vertex.throughput * result;
    }

    fn ao(self: *const Self, vertex: *const Vertex, isec: *const Intersection, worker: *Worker) Vec4f {
        const num_samples_reciprocal = 1.0 / @as(f32, @floatFromInt(self.settings.num_samples));
        const radius = self.settings.radius;

        var result: f32 = 0.0;
        var sampler = worker.pickSampler(0);

        const mat_sample = vertex.sample(isec, sampler, .Off, worker);

        if (worker.aov.active()) {
            worker.commonAOV(vertex, isec, &mat_sample);
        }

        const origin = isec.offsetP(mat_sample.super().geometricNormal());

        var occlusion_probe: Probe = undefined;
        occlusion_probe.time = vertex.probe.time;

        var i = self.settings.num_samples;
        while (i > 0) : (i -= 1) {
            const sample = sampler.sample2D();

            const os = math.smpl.hemisphereCosine(sample);
            const ws = mat_sample.super().frame.frameToWorld(os);

            occlusion_probe.ray.origin = origin;
            occlusion_probe.ray.setDirection(ws, radius);

            if (worker.scene.visibility(&occlusion_probe, sampler, worker)) |_| {
                result += num_samples_reciprocal;
            }

            sampler.incrementSample();
        }

        return .{ result, result, result, 1.0 };
    }

    fn vector(self: *const Self, vertex: *const Vertex, isec: *const Intersection, worker: *Worker) Vec4f {
        const wo = -vertex.probe.ray.direction;

        const sampler = worker.pickSampler(0);

        const mat_sample = vertex.sample(isec, sampler, .Off, worker);

        if (worker.aov.active()) {
            worker.commonAOV(vertex, isec, &mat_sample);
        }

        var vec: Vec4f = undefined;

        switch (self.settings.value) {
            .Tangent => vec = isec.t,
            .Bitangent => vec = isec.b,
            .GeometricNormal => vec = isec.geo_n,
            .ShadingNormal => {
                if (!mat_sample.super().sameHemisphere(wo)) {
                    return .{ 0.0, 0.0, 0.0, 1.0 };
                }

                vec = mat_sample.super().shadingNormal();
            },
            else => return .{ 0.0, 0.0, 0.0, 1.0 },
        }

        vec = .{ vec[0], vec[1], vec[2], 1.0 };

        return math.clamp4(@as(Vec4f, @splat(0.5)) * (vec + @as(Vec4f, @splat(1.0))), 0.0, 1.0);
    }

    fn lightSampleCount(self: *const Self, vertex: *const Vertex, isec: *const Intersection, worker: *Worker) Vec4f {
        _ = self;

        var sampler = worker.pickSampler(0);

        const mat_sample = vertex.sample(isec, sampler, .Off, worker);

        const n = mat_sample.super().geometricNormal();
        const p = isec.offsetP(n);

        var lights_buffer: Scene.Lights = undefined;
        const lights = worker.scene.randomLightSpatial(p, n, false, sampler.sample1D(), true, &lights_buffer);

        const r = @as(f32, @floatFromInt(lights.len)) / @as(f32, @floatFromInt(lights_buffer.len));

        return .{ r, r, r, 1.0 };
    }

    fn side(self: *const Self, vertex: *const Vertex, isec: *const Intersection, worker: *Worker) Vec4f {
        _ = self;

        const sampler = worker.pickSampler(0);

        const mat_sample = vertex.sample(isec, sampler, .Off, worker);

        const super = mat_sample.super();
        const n = math.cross3(super.shadingTangent(), super.shadingBitangent());
        const same_side = math.dot3(n, super.shadingNormal()) > 0.0;
        return if (same_side) .{ 0.2, 1.0, 0.1, 0.0 } else .{ 1.0, 0.1, 0.2, 0.0 };
    }

    fn photons(self: *const Self, vertex: *Vertex, isec: *Intersection, worker: *Worker) Vec4f {
        var bxdf_samples: bxdf.Samples = undefined;

        while (true) {
            var sampler = worker.pickSampler(vertex.probe.depth);

            const mat_sample = vertex.sample(isec, sampler, .Off, worker);

            const gather_photons = vertex.state.started_specular or self.settings.photons_not_only_through_specular;
            if (mat_sample.canEvaluate() and vertex.state.forward and gather_photons) {
                worker.addPhoton(vertex.throughput * worker.photonLi(isec, &mat_sample, sampler));
            }

            const sample_results = mat_sample.sample(sampler, false, &bxdf_samples);
            if (0 == sample_results.len) {
                break;
            }

            const sample_result = sample_results[0];

            if (sample_result.class.specular) {
                vertex.state.treat_as_singular = true;

                if (vertex.state.primary_ray) {
                    vertex.state.started_specular = true;
                }
            } else if (!sample_result.class.straight) {
                vertex.state.treat_as_singular = false;
                vertex.state.primary_ray = false;

                if (!sample_result.class.transmission) {
                    vertex.state.forward = false;
                }
            }

            vertex.probe.ray.origin = isec.offsetP(sample_result.wi);
            vertex.probe.ray.setDirection(sample_result.wi, ro.Ray_max_t);
            vertex.probe.depth += 1;

            if (vertex.probe.depth >= self.settings.max_bounces or !vertex.state.forward) {
                break;
            }

            vertex.throughput_old = vertex.throughput;
            vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

            if (!sample_result.class.straight) {
                vertex.state.from_subsurface = isec.subsurface();
                vertex.origin = isec.p;
            }

            if (0.0 == vertex.probe.wavelength) {
                vertex.probe.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                vertex.interfaceChange(isec, sample_result.wi, sampler, worker.scene);
            }

            if (!worker.nextEvent(false, vertex, isec, sampler)) {
                break;
            }

            sampler.incrementPadding();
        }

        return @splat(0.0);
    }
};
