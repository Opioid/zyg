const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Scene = @import("../../../scene/scene.zig").Scene;
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
        caustics_path: bool,
        caustics_resolve: CausticsResolve,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: *const Self, input: Vertex, worker: *Worker) Vec4f {
        var vertex = input;
        var result: Vec4f = @splat(0.0);

        while (true) {
            var sampler = worker.pickSampler(vertex.probe.depth);

            var isec: Intersection = undefined;
            if (!worker.nextEvent(false, &vertex, &isec, sampler)) {
                break;
            }

            const energy = self.connectLight(&vertex, &isec, sampler, worker.scene);
            result += vertex.throughput * energy;

            if (vertex.probe.depth >= self.settings.max_bounces or .Absorb == isec.event) {
                break;
            }

            if (vertex.probe.depth >= self.settings.min_bounces) {
                const rr = hlp.russianRoulette(vertex.throughput, vertex.throughput_old, sampler.sample1D()) orelse break;
                vertex.throughput /= @splat(rr);
            }

            const caustics = self.causticsResolve(vertex.state);
            const mat_sample = vertex.sample(&isec, sampler, caustics, worker);

            if (worker.aov.active()) {
                worker.commonAOV(&vertex, &isec, &mat_sample);
            }

            var bxdf_samples: bxdf.Samples = undefined;
            const sample_results = mat_sample.sample(sampler, false, &bxdf_samples);
            if (0 == sample_results.len) {
                break;
            }

            const sample_result = sample_results[0];

            if (sample_result.class.specular) {
                vertex.state.treat_as_singular = true;
            } else if (!sample_result.class.straight) {
                vertex.state.treat_as_singular = false;
                vertex.state.primary_ray = false;
            }

            vertex.throughput_old = vertex.throughput;
            vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

            vertex.probe.ray.origin = isec.offsetP(sample_result.wi);
            vertex.probe.ray.setDirection(sample_result.wi, ro.Ray_max_t);
            vertex.probe.depth += 1;

            if (!sample_result.class.straight) {
                vertex.state.from_subsurface = isec.subsurface();
                vertex.origin = isec.p;
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

    fn connectLight(
        self: *const Self,
        vertex: *const Vertex,
        isec: *const Intersection,
        sampler: *Sampler,
        scene: *const Scene,
    ) Vec4f {
        if (!self.settings.caustics_path and vertex.state.treat_as_singular and !vertex.state.primary_ray) {
            return @splat(0.0);
        }

        const p = vertex.probe.ray.origin;
        const wo = -vertex.probe.ray.direction;
        return isec.evaluateRadiance(p, wo, sampler, scene) orelse @splat(0.0);
    }

    fn causticsResolve(self: *const Self, state: Vertex.State) CausticsResolve {
        if (!state.primary_ray) {
            if (!self.settings.caustics_path) {
                return .Off;
            }

            return self.settings.caustics_resolve;
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
