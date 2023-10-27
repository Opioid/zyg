const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Worker = @import("../../worker.zig").Worker;
const CausticsResolve = @import("../../../scene/renderstate.zig").CausticsResolve;
const bxdf = @import("../../../scene/material/bxdf.zig");
const hlp = @import("../helper.zig");
const ro = @import("../../../scene/ray_offset.zig");
const Intersection = @import("../../../scene/shape/intersection.zig").Intersection;
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
        caustics_resolve: CausticsResolve,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: *const Self, input: Vertex, worker: *Worker) Vec4f {
        var vertex = input;
        var result: Vec4f = @splat(0.0);

        var bxdf_samples: bxdf.Samples = undefined;

        while (true) {
            var sampler = worker.pickSampler(vertex.probe.depth);

            var isec: Intersection = undefined;
            if (!worker.nextEvent(&vertex, &isec, sampler)) {
                break;
            }

            const wo = -vertex.probe.ray.direction;

            const energy: Vec4f = isec.evaluateRadiance(vertex.probe.ray.origin, wo, sampler, worker.scene) orelse @splat(0.0);

            result += vertex.throughput * energy;

            const caustics = self.causticsResolve(vertex.state);

            const mat_sample = vertex.sample(&isec, sampler, caustics, worker);

            if (worker.aov.active()) {
                worker.commonAOV(&vertex, &isec, &mat_sample);
            }

            if (vertex.probe.depth >= self.settings.max_bounces or .Absorb == isec.event) {
                break;
            }

            if (vertex.probe.depth >= self.settings.min_bounces) {
                const rr = hlp.russianRoulette(vertex.throughput, vertex.throughput_old, sampler.sample1D()) orelse break;
                vertex.throughput /= @splat(rr);
            }

            const sample_results = mat_sample.sample(sampler, false, &bxdf_samples);
            if (0 == sample_results.len) {
                break;
            }

            const sample_result = sample_results[0];
            if (sample_result.class.specular and .Full != caustics) {
                break;
            }

            if (!sample_result.class.specular and !sample_result.class.straight) {
                vertex.state.primary_ray = false;
            }

            vertex.throughput_old = vertex.throughput;
            vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

            vertex.probe.depth += 1;

            if (sample_result.class.straight) {
                vertex.probe.ray.setMinMaxT(isec.offsetT(vertex.probe.ray.maxT()), ro.Ray_max_t);
            } else {
                vertex.probe.ray.origin = isec.offsetP(sample_result.wi);
                vertex.probe.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                vertex.state.direct = false;
                vertex.state.from_subsurface = isec.subsurface();
            }

            if (0.0 == vertex.probe.wavelength) {
                vertex.probe.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                vertex.interfaceChange(&isec, sample_result.wi, sampler, worker.scene);
            }

            vertex.state.transparent = vertex.state.transparent and (sample_result.class.transmission or sample_result.class.straight);

            sampler.incrementPadding();
        }

        return hlp.composeAlpha(result, vertex.throughput, vertex.state.transparent);
    }

    fn causticsResolve(self: *const Self, state: Vertex.State) CausticsResolve {
        const pr = state.primary_ray;
        const r = self.settings.caustics_resolve;

        if (!pr) {
            if (self.settings.avoid_caustics) {
                return .Off;
            }

            return r;
        }

        return .Full;
    }
};

pub const Factory = struct {
    settings: Pathtracer.Settings,

    pub fn create(self: Factory) Pathtracer {
        return .{ .settings = self.settings };
    }
};
