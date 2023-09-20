const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Intersector = Vertex.Intersector;
const Scene = @import("../../../scene/scene.zig").Scene;
const Worker = @import("../../worker.zig").Worker;
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

    pub fn li(self: *const Self, vertex: *Vertex, worker: *Worker) Vec4f {
        var sampler = worker.pickSampler(0);

        if (!worker.nextEvent(vertex, @splat(1.0), sampler)) {
            return @splat(0.0);
        }

        const result = switch (self.settings.value) {
            .AO => self.ao(vertex, worker),
            .Tangent, .Bitangent, .GeometricNormal, .ShadingNormal => self.vector(vertex, worker),
            .LightSampleCount => self.lightSampleCount(vertex, worker),
            .Side => self.side(vertex, worker),
            .Photons => self.photons(vertex, worker),
        };

        return vertex.isec.hit.vol_tr * result;
    }

    fn ao(self: *const Self, vertex: *const Vertex, worker: *Worker) Vec4f {
        const num_samples_reciprocal = 1.0 / @as(f32, @floatFromInt(self.settings.num_samples));
        const radius = self.settings.radius;

        var result: f32 = 0.0;
        var sampler = worker.pickSampler(0);

        const wo = -vertex.isec.ray.direction;
        const mat_sample = vertex.sample(wo, sampler, .Off, worker);

        if (worker.aov.active()) {
            worker.commonAOV(@splat(1.0), vertex, &mat_sample);
        }

        const origin = vertex.isec.hit.offsetP(mat_sample.super().geometricNormal());

        var occlusion_isec: Vertex.Intersector = undefined;
        occlusion_isec.time = vertex.isec.time;

        var i = self.settings.num_samples;
        while (i > 0) : (i -= 1) {
            const sample = sampler.sample2D();

            const t = mat_sample.super().shadingTangent();
            const b = mat_sample.super().shadingBitangent();
            const n = mat_sample.super().shadingNormal();

            const ws = math.smpl.orientedHemisphereCosine(sample, t, b, n);

            occlusion_isec.ray.origin = origin;
            occlusion_isec.ray.setDirection(ws, radius);

            if (worker.scene.visibility(&occlusion_isec, sampler, worker)) |_| {
                result += num_samples_reciprocal;
            }

            sampler.incrementSample();
        }

        return .{ result, result, result, 1.0 };
    }

    fn vector(self: *const Self, vertex: *const Vertex, worker: *Worker) Vec4f {
        var sampler = worker.pickSampler(0);

        const wo = -vertex.isec.ray.direction;
        const mat_sample = vertex.sample(wo, sampler, .Off, worker);

        var vec: Vec4f = undefined;

        switch (self.settings.value) {
            .Tangent => vec = vertex.isec.hit.t,
            .Bitangent => vec = vertex.isec.hit.b,
            .GeometricNormal => vec = vertex.isec.hit.geo_n,
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

    fn lightSampleCount(self: *const Self, vertex: *const Vertex, worker: *Worker) Vec4f {
        _ = self;

        var sampler = worker.pickSampler(0);

        const wo = -vertex.isec.ray.direction;
        const mat_sample = vertex.sample(wo, sampler, .Off, worker);

        const n = mat_sample.super().geometricNormal();
        const p = vertex.isec.hit.offsetP(n);

        var lights_buffer: Scene.Lights = undefined;
        const lights = worker.scene.randomLightSpatial(p, n, false, sampler.sample1D(), true, &lights_buffer);

        const r = @as(f32, @floatFromInt(lights.len)) / @as(f32, @floatFromInt(lights_buffer.len));

        return .{ r, r, r, 1.0 };
    }

    fn side(self: *const Self, vertex: *const Vertex, worker: *Worker) Vec4f {
        _ = self;

        var sampler = worker.pickSampler(0);

        const wo = -vertex.isec.ray.direction;
        const mat_sample = vertex.sample(wo, sampler, .Off, worker);

        const super = mat_sample.super();
        const n = math.cross3(super.shadingTangent(), super.shadingBitangent());
        const same_side = math.dot3(n, super.shadingNormal()) > 0.0;
        return if (same_side) .{ 0.2, 1.0, 0.1, 0.0 } else .{ 1.0, 0.1, 0.2, 0.0 };
    }

    fn photons(self: *const Self, vertex: *Vertex, worker: *Worker) Vec4f {
        var throughput: Vec4f = @splat(1.0);

        var i: u32 = 0;
        while (true) : (i += 1) {
            var sampler = worker.pickSampler(vertex.isec.depth);

            const mat_sample = worker.sampleMaterial(vertex, sampler, 0.0, .Off);

            if (mat_sample.isPureEmissive()) {
                break;
            }

            const sample_result = mat_sample.sample(sampler);
            if (0.0 == sample_result.pdf) {
                break;
            }

            if (sample_result.class.specular) {} else if (!sample_result.class.straight and !sample_result.class.transmission) {
                if (vertex.state.primary_ray) {
                    vertex.state.primary_ray = false;

                    const indirect = !vertex.state.direct and 0 != vertex.isec.depth;
                    if (self.settings.photons_not_only_through_specular or indirect) {
                        worker.addPhoton(throughput * worker.photonLi(vertex.isec.hit, &mat_sample, sampler));
                        break;
                    }
                }
            }

            if (!(sample_result.class.straight and sample_result.class.transmission)) {
                vertex.isec.depth += 1;
            }

            if (vertex.isec.depth >= self.settings.max_bounces) {
                break;
            }

            if (sample_result.class.straight) {
                vertex.isec.ray.setMinMaxT(ro.offsetF(vertex.isec.ray.maxT()), ro.Ray_max_t);
            } else {
                vertex.isec.ray.origin = vertex.isec.hit.offsetP(sample_result.wi);
                vertex.isec.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                vertex.state.direct = false;
                vertex.state.from_subsurface = false;
            }

            if (0.0 == vertex.isec.wavelength) {
                vertex.isec.wavelength = sample_result.wavelength;
            }

            throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

            if (sample_result.class.transmission) {
                vertex.interfaceChange(sample_result.wi, sampler, worker.scene);
            }

            vertex.state.from_subsurface = vertex.state.from_subsurface or vertex.isec.hit.subsurface();

            if (!worker.nextEvent(vertex, throughput, sampler)) {
                break;
            }

            throughput *= vertex.isec.hit.vol_tr;

            sampler.incrementPadding();
        }

        return @splat(0.0);
    }
};

pub const Factory = struct {
    settings: AOV.Settings,

    pub fn create(self: Factory) AOV {
        return .{ .settings = self.settings };
    }
};
