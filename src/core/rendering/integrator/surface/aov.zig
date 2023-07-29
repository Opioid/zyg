const Vertex = @import("../../../scene/vertex.zig").Vertex;
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

    pub fn li(self: *Self, vertex: *Vertex, worker: *Worker) Vec4f {
        var isec = Intersection{};
        var sampler = worker.pickSampler(0);

        if (!worker.nextEvent(vertex, @splat(4, @as(f32, 1.0)), &isec, sampler)) {
            return @splat(4, @as(f32, 0.0));
        }

        const result = switch (self.settings.value) {
            .AO => self.ao(vertex.*, isec, worker),
            .Tangent, .Bitangent, .GeometricNormal, .ShadingNormal => self.vector(vertex.*, isec, worker),
            .LightSampleCount => self.lightSampleCount(vertex.*, isec, worker),
            .Side => self.side(vertex.*, isec, worker),
            .Photons => self.photons(vertex, &isec, worker),
        };

        return isec.volume.tr * result;
    }

    fn ao(self: *Self, vertex: Vertex, isec: Intersection, worker: *Worker) Vec4f {
        const num_samples_reciprocal = 1.0 / @as(f32, @floatFromInt(self.settings.num_samples));
        const radius = self.settings.radius;

        var result: f32 = 0.0;
        var sampler = worker.pickSampler(0);

        const wo = -vertex.ray.direction;
        const mat_sample = isec.sample(wo, vertex, sampler, .Off, worker);

        if (worker.aov.active()) {
            worker.commonAOV(@splat(4, @as(f32, 1.0)), vertex, isec, &mat_sample);
        }

        const origin = isec.offsetPN(mat_sample.super().geometricNormal(), false);

        var occlusion_vertex: Vertex = undefined;
        occlusion_vertex.time = vertex.time;

        var i = self.settings.num_samples;
        while (i > 0) : (i -= 1) {
            const sample = sampler.sample2D();

            const t = mat_sample.super().shadingTangent();
            const b = mat_sample.super().shadingBitangent();
            const n = mat_sample.super().shadingNormal();

            const ws = math.smpl.orientedHemisphereCosine(sample, t, b, n);

            occlusion_vertex.ray.origin = origin;
            occlusion_vertex.ray.setDirection(ws, radius);

            if (worker.scene.visibility(occlusion_vertex, sampler, worker)) |_| {
                result += num_samples_reciprocal;
            }

            sampler.incrementSample();
        }

        return .{ result, result, result, 1.0 };
    }

    fn vector(self: *Self, vertex: Vertex, isec: Intersection, worker: *Worker) Vec4f {
        var sampler = worker.pickSampler(0);

        const wo = -vertex.ray.direction;
        const mat_sample = isec.sample(wo, vertex, sampler, .Off, worker);

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

        vec = .{ vec[0], vec[1], vec[2], 1.0 };

        return math.clamp4(@splat(4, @as(f32, 0.5)) * (vec + @splat(4, @as(f32, 1.0))), 0.0, 1.0);
    }

    fn lightSampleCount(self: *Self, vertex: Vertex, isec: Intersection, worker: *Worker) Vec4f {
        _ = self;

        var sampler = worker.pickSampler(0);

        const wo = -vertex.ray.direction;
        const mat_sample = isec.sample(wo, vertex, sampler, .Off, worker);

        const n = mat_sample.super().geometricNormal();
        const p = isec.offsetPN(n, false);

        const lights = worker.randomLightSpatial(p, n, false, sampler.sample1D(), true);

        const r = @as(f32, @floatFromInt(lights.len)) / @as(f32, @floatFromInt(worker.lights.len));

        return .{ r, r, r, 1.0 };
    }

    fn side(self: *Self, vertex: Vertex, isec: Intersection, worker: *Worker) Vec4f {
        _ = self;

        var sampler = worker.pickSampler(0);

        const wo = -vertex.ray.direction;
        const mat_sample = isec.sample(wo, vertex, sampler, .Off, worker);

        const super = mat_sample.super();
        const n = math.cross3(super.shadingTangent(), super.shadingBitangent());
        const same_side = math.dot3(n, super.shadingNormal()) > 0.0;
        return if (same_side) .{ 0.2, 1.0, 0.1, 0.0 } else .{ 1.0, 0.1, 0.2, 0.0 };
    }

    fn photons(self: *Self, vertex: *Vertex, isec: *Intersection, worker: *Worker) Vec4f {
        var throughput = @splat(4, @as(f32, 1.0));

        var i: u32 = 0;
        while (true) : (i += 1) {
            var sampler = worker.pickSampler(vertex.depth);

            const mat_sample = worker.sampleMaterial(vertex.*, isec.*, sampler, 0.0, .Off);

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

                    const indirect = !vertex.state.direct and 0 != vertex.depth;
                    if (self.settings.photons_not_only_through_specular or indirect) {
                        worker.addPhoton(throughput * worker.photonLi(isec.*, &mat_sample, sampler));
                        break;
                    }
                }
            }

            if (!(sample_result.class.straight and sample_result.class.transmission)) {
                vertex.depth += 1;
            }

            if (vertex.depth >= self.settings.max_bounces) {
                break;
            }

            if (sample_result.class.straight) {
                vertex.ray.setMinMaxT(ro.offsetF(vertex.ray.maxT()), ro.Ray_max_t);
            } else {
                vertex.ray.origin = isec.offsetP(sample_result.wi);
                vertex.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                vertex.state.direct = false;
                vertex.state.from_subsurface = false;
            }

            if (0.0 == vertex.wavelength) {
                vertex.wavelength = sample_result.wavelength;
            }

            throughput *= sample_result.reflection / @splat(4, sample_result.pdf);

            if (sample_result.class.transmission) {
                worker.interfaceChange(sample_result.wi, isec.*, sampler);
            }

            vertex.state.from_subsurface = vertex.state.from_subsurface or isec.subsurface();

            if (!worker.nextEvent(vertex, throughput, isec, sampler)) {
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
