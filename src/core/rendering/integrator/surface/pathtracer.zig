const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Intersector = Vertex.Intersector;
const Worker = @import("../../worker.zig").Worker;
const CausticsResolve = @import("../../../scene/renderstate.zig").CausticsResolve;
const bxdf = @import("../../../scene/material/bxdf.zig");
const hlp = @import("../helper.zig");
const ro = @import("../../../scene/ray_offset.zig");
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

    pub fn li(self: *const Self, vertex: *Vertex, worker: *Worker) Vec4f {
        var throughput: Vec4f = @splat(1.0);
        var old_throughput: Vec4f = @splat(1.0);
        var result: Vec4f = @splat(0.0);

        var bxdf_samples: bxdf.Samples = undefined;

        while (true) {
            var sampler = worker.pickSampler(vertex.isec.depth);

            if (!worker.nextEvent(vertex, throughput, sampler)) {
                break;
            }

            throughput *= vertex.isec.hit.vol_tr;

            const wo = -vertex.isec.ray.direction;

            var pure_emissive: bool = undefined;
            const energy: Vec4f = vertex.isec.evaluateRadiance(
                wo,
                sampler,
                worker.scene,
                &pure_emissive,
            ) orelse @splat(0.0);

            result += throughput * energy;

            if (pure_emissive) {
                break;
            }

            const caustics = self.causticsResolve(vertex.state);

            const mat_sample = worker.sampleMaterial(vertex, sampler, 0.0, caustics);

            if (worker.aov.active()) {
                worker.commonAOV(throughput, vertex, &mat_sample);
            }

            if (vertex.isec.depth >= self.settings.max_bounces) {
                break;
            }

            if (vertex.isec.depth >= self.settings.min_bounces) {
                if (hlp.russianRoulette(&throughput, old_throughput, sampler.sample1D())) {
                    break;
                }
            }

            const sample_results = mat_sample.sample(sampler, false, &bxdf_samples);
            if (0 == sample_results.len) {
                break;
            }

            const sample_result = sample_results[0];
            if (math.allLessEqualZero3(sample_result.reflection) or
                (sample_result.class.specular and .Full != caustics))
            {
                break;
            }

            if (!sample_result.class.specular and !sample_result.class.straight) {
                vertex.state.primary_ray = false;
            }

            old_throughput = throughput;
            throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

            if (!(sample_result.class.straight and sample_result.class.transmission)) {
                vertex.isec.depth += 1;
            }

            if (sample_result.class.straight) {
                vertex.isec.ray.setMinMaxT(vertex.isec.hit.offsetT(vertex.isec.ray.maxT()), ro.Ray_max_t);
            } else {
                vertex.isec.ray.origin = vertex.isec.hit.offsetP(sample_result.wi);
                vertex.isec.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                vertex.state.direct = false;
                vertex.state.from_subsurface = vertex.isec.hit.subsurface();
            }

            if (0.0 == vertex.isec.wavelength) {
                vertex.isec.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                vertex.interfaceChange(sample_result.wi, sampler, worker.scene);
            }

            vertex.state.transparent = vertex.state.transparent and (sample_result.class.transmission or sample_result.class.straight);

            sampler.incrementPadding();
        }

        return hlp.composeAlpha(result, throughput, vertex.state.transparent);
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
