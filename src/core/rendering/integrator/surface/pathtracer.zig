const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Scene = @import("../../../scene/scene.zig").Scene;
const Worker = @import("../../worker.zig").Worker;
const CausticsResolve = @import("../../../scene/renderstate.zig").CausticsResolve;
const bxdf = @import("../../../scene/material/bxdf.zig");
const hlp = @import("../helper.zig");
const IValue = hlp.IValue;
const ro = @import("../../../scene/ray_offset.zig");
const Fragment = @import("../../../scene/shape/intersection.zig").Fragment;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Pathtracer = struct {
    pub const Settings = struct {
        max_depth: hlp.Depth,
        caustics_path: bool,
        caustics_resolve: CausticsResolve,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: Self, input: *const Vertex, worker: *Worker) IValue {
        const max_depth = self.settings.max_depth;

        var vertex = input.*;

        var result: IValue = .{};

        while (true) {
            const total_depth = vertex.probe.depth.total();

            var sampler = worker.pickSampler(total_depth);

            var frag: Fragment = undefined;
            if (!worker.nextEvent(&vertex, &frag, sampler)) {
                break;
            }

            const energy = self.connectLight(&vertex, &frag, sampler, worker.scene);
            const weighted_energy = vertex.throughput * energy;

            if (vertex.state.treat_as_singular) {
                result.emission += weighted_energy;
            } else {
                result.reflection += weighted_energy;
            }

            if (vertex.probe.depth.surface >= max_depth.surface or vertex.probe.depth.volume >= max_depth.volume or .Absorb == frag.event) {
                break;
            }

            if (hlp.russianRoulette(&vertex.throughput, sampler.sample1D())) {
                break;
            }

            const caustics = self.causticsResolve(vertex.state);
            const mat_sample = vertex.sample(&frag, sampler, caustics, worker);

            if (worker.aov.active()) {
                worker.commonAOV(&vertex, &frag, &mat_sample);
            }

            var bxdf_samples: bxdf.Samples = undefined;
            const sample_results = mat_sample.sample(sampler, false, &bxdf_samples);
            if (0 == sample_results.len) {
                vertex.throughput = @splat(0.0);
                break;
            }

            const sample_result = sample_results[0];

            if (sample_result.class.specular) {
                vertex.state.treat_as_singular = true;
            } else if (!sample_result.class.straight) {
                vertex.state.treat_as_singular = false;
                vertex.state.primary_ray = false;
            }

            if (!sample_result.class.straight) {
                vertex.origin = frag.p;
            }

            vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

            vertex.probe.ray.origin = frag.offsetP(sample_result.wi);
            vertex.probe.ray.setDirection(sample_result.wi, ro.Ray_max_t);
            vertex.probe.depth.increment(&frag);

            if (0.0 == vertex.probe.wavelength) {
                vertex.probe.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                vertex.interfaceChange(&frag, sample_result.wi, sampler, worker.scene);
            }

            vertex.state.transparent = vertex.state.transparent and (sample_result.class.transmission or sample_result.class.straight);

            sampler.incrementPadding();
        }

        result.reflection[3] = hlp.composeAlpha(vertex.throughput, vertex.state.transparent);
        return result;
    }

    fn connectLight(
        self: Self,
        vertex: *const Vertex,
        frag: *const Fragment,
        sampler: *Sampler,
        scene: *const Scene,
    ) Vec4f {
        if (!self.settings.caustics_path and vertex.state.treat_as_singular and !vertex.state.primary_ray) {
            return @splat(0.0);
        }

        const p = vertex.origin;
        const wo = -vertex.probe.ray.direction;
        return frag.evaluateRadiance(p, wo, sampler, scene) orelse @splat(0.0);
    }

    fn causticsResolve(self: Self, state: Vertex.State) CausticsResolve {
        if (!state.primary_ray) {
            if (!self.settings.caustics_path) {
                return .Off;
            }

            return self.settings.caustics_resolve;
        }

        return .Full;
    }
};
