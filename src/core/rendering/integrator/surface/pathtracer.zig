const Context = @import("../../../scene/context.zig").Context;
const Vertex = @import("../../../scene/vertex.zig").Vertex;
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

    pub fn li(self: Self, input: Vertex, worker: *Worker) IValue {
        const max_depth = self.settings.max_depth;

        var vertex = input;

        var result: IValue = .{};

        while (true) {
            const total_depth = vertex.probe.depth.total();

            var sampler = worker.pickSampler(total_depth);

            var frag: Fragment = undefined;
            worker.context.nextEvent(&vertex, &frag, sampler);
            if (.Abort == frag.event) {
                break;
            }

            const energy = self.connectLight(&vertex, &frag, sampler, worker.context);
            const weighted_energy = vertex.throughput * energy;

            const indirect_light_depth = total_depth - @as(u32, if (vertex.state.exit_sss) 1 else 0);
            result.add(weighted_energy, indirect_light_depth, 1, vertex.state.treat_as_singular);

            if (!frag.hit() or
                vertex.probe.depth.surface >= max_depth.surface or
                vertex.probe.depth.volume >= max_depth.volume or
                .Absorb == frag.event)
            {
                break;
            }

            if (hlp.russianRoulette(&vertex.throughput, sampler.sample1D())) {
                break;
            }

            const caustics = self.causticsResolve(vertex.state);
            const mat_sample = vertex.sample(&frag, sampler, caustics, worker.context);

            if (worker.aov.active()) {
                worker.commonAOV(&vertex, &frag, &mat_sample);
            }

            vertex.state.exit_sss = .ExitSSS == frag.event;

            var bxdf_samples: bxdf.Samples = undefined;
            const sample_results = mat_sample.sample(sampler, 1, &bxdf_samples);
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

            vertex.probe.ray = frag.offsetRay(sample_result.wi, ro.RayMaxT);
            vertex.probe.depth.increment(&frag);

            if (0.0 == vertex.probe.wavelength) {
                vertex.probe.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                vertex.interfaceChange(sample_result.wi, &frag, &mat_sample, worker.context.scene);
            }

            vertex.state.transparent = vertex.state.transparent and (sample_result.class.transmission or sample_result.class.straight);

            sampler.incrementPadding();
        }

        result.direct[3] = hlp.composeAlpha(vertex.throughput, vertex.state.transparent);
        return result;
    }

    fn connectLight(self: Self, vertex: *Vertex, frag: *const Fragment, sampler: *Sampler, context: Context) Vec4f {
        if (!self.settings.caustics_path and vertex.state.treat_as_singular and !vertex.state.primary_ray) {
            return @splat(0.0);
        }

        var energy: Vec4f = @splat(0.0);

        if (frag.hit()) {
            energy += vertex.evaluateRadiance(frag, sampler, context) orelse @splat(0.0);
        }

        // Do this to avoid MIS calculation, which this integrator doesn't need
        const treat_as_singular = vertex.state.treat_as_singular;
        vertex.state.treat_as_singular = true;

        var light_frag: Fragment = undefined;
        light_frag.event = .Pass;

        energy += context.emission(vertex, &light_frag, 0.0, sampler);

        var inf_frag: Fragment = undefined;
        inf_frag.event = .Pass;

        for (context.scene.infinite_props.items) |prop| {
            if (!context.propIntersect(prop, vertex.probe, sampler, &inf_frag)) {
                continue;
            }

            context.propInterpolateFragment(prop, vertex.probe, &inf_frag);

            energy += vertex.evaluateRadiance(&inf_frag, sampler, context) orelse continue;
        }

        vertex.state.treat_as_singular = treat_as_singular;

        return energy;
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
