const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Probe = Vertex.Probe;
const Fragment = @import("../../../scene/shape/intersection.zig").Fragment;
const ro = @import("../../../scene/ray_offset.zig");
const Scene = @import("../../../scene/scene.zig").Scene;
const Worker = @import("../../worker.zig").Worker;
const hlp = @import("../helper.zig");
const bxdf = @import("../../../scene/material/bxdf.zig");
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
        max_depth: hlp.Depth,
        light_sampling: hlp.LightSampling,

        value: Value,

        num_samples: u32,

        radius: f32,

        photons_not_only_through_specular: bool,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: *const Self, input: *const Vertex, worker: *Worker) Vec4f {
        var vertex = input.*;

        const sampler = worker.pickSampler(0);

        var frag: Fragment = undefined;
        if (!worker.nextEvent(&vertex, &frag, sampler)) {
            return @splat(0.0);
        }

        const result = switch (self.settings.value) {
            .AO => self.ao(&vertex, &frag, worker),
            .Tangent, .Bitangent, .GeometricNormal, .ShadingNormal => self.vector(&vertex, &frag, worker),
            .LightSampleCount => self.lightSampleCount(&vertex, &frag, worker),
            .Side => self.side(&vertex, &frag, worker),
            .Photons => self.photons(&vertex, &frag, worker),
        };

        return vertex.throughput * result;
    }

    fn ao(self: *const Self, vertex: *const Vertex, frag: *const Fragment, worker: *Worker) Vec4f {
        const num_samples_reciprocal = 1.0 / @as(f32, @floatFromInt(self.settings.num_samples));
        const radius = self.settings.radius;

        var result: f32 = 0.0;
        var sampler = worker.pickSampler(0);

        const mat_sample = vertex.sample(frag, sampler, .Off, worker);

        if (worker.aov.active()) {
            worker.commonAOV(vertex, frag, &mat_sample);
        }

        const origin = frag.offsetP(mat_sample.super().geometricNormal());

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

    fn vector(self: *const Self, vertex: *const Vertex, frag: *const Fragment, worker: *Worker) Vec4f {
        const wo = -vertex.probe.ray.direction;

        const sampler = worker.pickSampler(0);

        const mat_sample = vertex.sample(frag, sampler, .Off, worker);

        if (worker.aov.active()) {
            worker.commonAOV(vertex, frag, &mat_sample);
        }

        var vec: Vec4f = undefined;

        switch (self.settings.value) {
            .Tangent => vec = frag.t,
            .Bitangent => vec = frag.b,
            .GeometricNormal => vec = frag.geo_n,
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

    fn lightSampleCount(self: *const Self, vertex: *const Vertex, frag: *const Fragment, worker: *Worker) Vec4f {
        var sampler = worker.pickSampler(0);

        const mat_sample = vertex.sample(frag, sampler, .Off, worker);

        const n = mat_sample.super().geometricNormal();
        const p = frag.offsetP(n);

        const split_threshold = self.settings.light_sampling.splitThreshold(vertex.probe.depth, 0);

        var lights_buffer: Scene.Lights = undefined;
        const lights = worker.scene.randomLightSpatial(p, n, false, sampler.sample1D(), split_threshold, &lights_buffer);

        const max_lights = worker.scene.light_tree.potentialMaxights();
        const r = @as(f32, @floatFromInt(lights.len)) / @as(f32, @floatFromInt(max_lights));

        return .{ r, r, r, 1.0 };
    }

    fn side(self: *const Self, vertex: *const Vertex, frag: *const Fragment, worker: *Worker) Vec4f {
        _ = self;

        const sampler = worker.pickSampler(0);

        const mat_sample = vertex.sample(frag, sampler, .Off, worker);

        const super = mat_sample.super();
        const n = math.cross3(super.shadingTangent(), super.shadingBitangent());
        const same_side = math.dot3(n, super.shadingNormal()) > 0.0;
        return if (same_side) .{ 0.2, 1.0, 0.1, 0.0 } else .{ 1.0, 0.1, 0.2, 0.0 };
    }

    fn photons(self: *const Self, vertex: *Vertex, frag: *Fragment, worker: *Worker) Vec4f {
        var bxdf_samples: bxdf.Samples = undefined;

        while (true) {
            const total_depth = vertex.probe.depth.total();

            var sampler = worker.pickSampler(total_depth);

            const mat_sample = vertex.sample(frag, sampler, .Off, worker);

            const gather_photons = vertex.state.started_specular or self.settings.photons_not_only_through_specular;
            if (mat_sample.canEvaluate() and vertex.state.forward and gather_photons) {
                worker.addPhoton(vertex.throughput * worker.photonLi(frag, &mat_sample, sampler));
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

            vertex.probe.ray.origin = frag.offsetP(sample_result.wi);
            vertex.probe.ray.setDirection(sample_result.wi, ro.Ray_max_t);
            vertex.probe.depth.increment(frag);

            if (vertex.probe.depth.surface >= self.settings.max_depth.surface or !vertex.state.forward) {
                break;
            }

            vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

            if (!sample_result.class.straight) {
                vertex.origin = frag.p;
            }

            if (0.0 == vertex.probe.wavelength) {
                vertex.probe.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                vertex.interfaceChange(frag, sample_result.wi, sampler, worker.scene);
            }

            if (!worker.nextEvent(vertex, frag, sampler)) {
                break;
            }

            sampler.incrementPadding();
        }

        return @splat(0.0);
    }
};
