const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Fragment = @import("../../../scene/shape/intersection.zig").Fragment;
const Probe = @import("../../../scene/shape/probe.zig").Probe;
const ro = @import("../../../scene/ray_offset.zig");
const Scene = @import("../../../scene/scene.zig").Scene;
const Shape = @import("../../../scene/shape/shape.zig").Shape;
const Worker = @import("../../worker.zig").Worker;
const hlp = @import("../helper.zig");
const IValue = hlp.IValue;
const bxdf = @import("../../../scene/material/bxdf.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Ray = math.Ray;
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

    pub fn li(self: Self, input: Vertex, worker: *Worker) IValue {
        var vertex = input;

        const sampler = worker.pickSampler(0);

        var frag: Fragment = undefined;
        worker.context.nextEvent(&vertex, &frag, sampler);
        if (.Abort == frag.event or !frag.hit()) {
            return .{};
        }

        const result = switch (self.settings.value) {
            .AO => self.ao(vertex, &frag, worker),
            .Tangent, .Bitangent, .GeometricNormal, .ShadingNormal => self.vector(vertex, &frag, worker),
            .LightSampleCount => self.lightSampleCount(vertex, &frag, worker),
            .Side => self.side(vertex, &frag, worker),
            .Photons => self.photons(&vertex, &frag, worker),
        };

        return .{ .direct = vertex.throughput * result, .indirect = @splat(0.0) };
    }

    fn ao(self: Self, vertex: Vertex, frag: *const Fragment, worker: *Worker) Vec4f {
        const num_samples_reciprocal = 1.0 / @as(f32, @floatFromInt(self.settings.num_samples));
        const radius = self.settings.radius;

        var result: f32 = 0.0;
        var sampler = worker.pickSampler(0);

        const mat_sample = vertex.sample(frag, sampler, .Off, worker.context);

        if (worker.aov.active()) {
            worker.commonAOV(&vertex, frag, &mat_sample);
        }

        const origin = frag.offsetP(mat_sample.super().geometricNormal());

        var occlusion_probe: Probe = undefined;
        occlusion_probe.time = vertex.probe.time;

        var i = self.settings.num_samples;
        while (i > 0) : (i -= 1) {
            const sample = sampler.sample2D();

            const os = math.smpl.hemisphereCosine(sample);
            const ws = mat_sample.super().frame.frameToWorld(os);

            occlusion_probe.ray = Ray.init(origin, ws, 0.0, radius);

            var tr: Vec4f = @splat(1.0);
            if (worker.context.scene.visibility(occlusion_probe, sampler, worker.context, &tr)) {
                result += num_samples_reciprocal;
            }

            sampler.incrementSample();
        }

        return .{ result, result, result, 1.0 };
    }

    fn vector(self: Self, vertex: Vertex, frag: *const Fragment, worker: *Worker) Vec4f {
        const wo = -vertex.probe.ray.direction;

        const sampler = worker.pickSampler(0);

        const mat_sample = vertex.sample(frag, sampler, .Off, worker.context);

        if (worker.aov.active()) {
            worker.commonAOV(&vertex, frag, &mat_sample);
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

        return math.clamp4(@as(Vec4f, @splat(0.5)) * (vec + @as(Vec4f, @splat(1.0))), @splat(0.0), @splat(1.0));
    }

    fn lightSampleCount(self: Self, vertex: Vertex, frag: *const Fragment, worker: *Worker) Vec4f {
        var sampler = worker.pickSampler(0);

        const mat_sample = vertex.sample(frag, sampler, .Off, worker.context);

        const n = mat_sample.super().geometricNormal();
        const p = frag.p;

        const translucent = mat_sample.isTranslucent();

        const split_threshold = self.settings.light_sampling.splitThreshold(vertex.probe.depth);

        var lights_buffer: Scene.Lights = undefined;
        const lights = worker.context.scene.randomLightSpatial(p, n, false, sampler.sample1D(), split_threshold, &lights_buffer);

        const max_light_samples = worker.context.scene.light_tree.potentialMaxLights(worker.context.scene); // * Shape.MaxSamples;

        var nun_samples: u32 = 0;

        for (lights) |l| {
            const light = worker.context.scene.light(l.offset);

            const trafo = worker.context.scene.propTransformationAt(light.prop, vertex.probe.time);

            var samples_buffer: Scene.SamplesTo = undefined;
            const samples = light.sampleTo(p, n, trafo, vertex.probe.time, translucent, split_threshold, sampler, worker.context.scene, &samples_buffer);

            nun_samples += @intCast(samples.len);
        }

        const r = @as(f32, @floatFromInt(nun_samples)) / @as(f32, @floatFromInt(max_light_samples));

        return .{ r, r, r, 1.0 };
    }

    fn side(self: Self, vertex: Vertex, frag: *const Fragment, worker: *Worker) Vec4f {
        _ = self;

        const sampler = worker.pickSampler(0);

        const mat_sample = vertex.sample(frag, sampler, .Off, worker.context);

        const super = mat_sample.super();
        const n = math.cross3(super.shadingTangent(), super.shadingBitangent());
        const same_side = math.dot3(n, super.shadingNormal()) > 0.0;
        return if (same_side) .{ 0.2, 1.0, 0.1, 0.0 } else .{ 1.0, 0.1, 0.2, 0.0 };
    }

    fn photons(self: Self, vertex: *Vertex, frag: *Fragment, worker: *Worker) Vec4f {
        var bxdf_samples: bxdf.Samples = undefined;

        var result: Vec4f = @splat(0.0);

        while (true) {
            const total_depth = vertex.probe.depth.total();

            var sampler = worker.pickSampler(total_depth);

            const mat_sample = vertex.sample(frag, sampler, .Off, worker.context);

            const gather_photons = vertex.state.started_specular or self.settings.photons_not_only_through_specular;
            if (mat_sample.canEvaluate() and gather_photons) {
                result += vertex.throughput * worker.photonLi(frag, &mat_sample, sampler);
            }

            const sample_results = mat_sample.sample(sampler, 1, &bxdf_samples);
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
            }

            vertex.probe.ray = frag.offsetRay(sample_result.wi, ro.RayMaxT);
            vertex.probe.depth.increment(frag);

            if (vertex.probe.depth.surface >= self.settings.max_depth.surface) {
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
                vertex.interfaceChange(sample_result.wi, frag, &mat_sample, worker.context.scene);
            }

            worker.context.nextEvent(vertex, frag, sampler);
            if (.Abort == frag.event or !frag.hit()) {
                break;
            }

            sampler.incrementPadding();
        }

        return result;
    }
};
