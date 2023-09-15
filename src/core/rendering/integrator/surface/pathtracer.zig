const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/shape/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const CausticsResolve = @import("../../../scene/renderstate.zig").CausticsResolve;
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

        var isec: Intersection = undefined;

        while (true) {
            var sampler = worker.pickSampler(vertex.depth);

            if (!worker.nextEvent(vertex, throughput, &isec, sampler)) {
                break;
            }

            throughput *= isec.vol_tr;

            const wo = -vertex.ray.direction;

            var pure_emissive: bool = undefined;
            const energy: Vec4f = isec.evaluateRadiance(
                vertex.ray.origin,
                wo,
                sampler,
                worker.scene,
                &pure_emissive,
            ) orelse @splat(0.0);

            result += throughput * energy;

            if (pure_emissive) {
                const vis_in_cam = isec.visibleInCamera(worker.scene);
                vertex.state.direct = vertex.state.direct and (!vis_in_cam and vertex.ray.maxT() >= ro.Ray_max_t);
                break;
            }

            const caustics = self.causticsResolve(vertex.state);

            const mat_sample = worker.sampleMaterial(
                vertex.*,
                isec,
                sampler,
                0.0,
                caustics,
            );

            if (worker.aov.active()) {
                worker.commonAOV(throughput, vertex.*, isec, &mat_sample);
            }

            if (vertex.depth >= self.settings.max_bounces) {
                break;
            }

            if (vertex.depth >= self.settings.min_bounces) {
                if (hlp.russianRoulette(&throughput, old_throughput, sampler.sample1D())) {
                    break;
                }
            }

            const sample_result = mat_sample.sample(sampler);
            if (0.0 == sample_result.pdf or math.allLessEqualZero3(sample_result.reflection)) {
                break;
            }

            if (sample_result.class.specular) {
                if (.Full != caustics) {
                    break;
                }
            } else if (!sample_result.class.straight) {
                vertex.state.primary_ray = false;
            }

            old_throughput = throughput;
            throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

            if (!(sample_result.class.straight and sample_result.class.transmission)) {
                vertex.depth += 1;
            }

            if (sample_result.class.straight) {
                vertex.ray.setMinMaxT(isec.offsetT(vertex.ray.maxT()), ro.Ray_max_t);
            } else {
                vertex.ray.origin = isec.offsetP(sample_result.wi);
                vertex.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                vertex.state.direct = false;
                vertex.state.from_subsurface = isec.subsurface();
            }

            if (0.0 == vertex.wavelength) {
                vertex.wavelength = sample_result.wavelength;
            }

            if (sample_result.class.transmission) {
                worker.interfaceChange(sample_result.wi, isec, sampler);
            }

            sampler.incrementPadding();
        }

        return hlp.composeAlpha(result, throughput, vertex.state.direct);
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
