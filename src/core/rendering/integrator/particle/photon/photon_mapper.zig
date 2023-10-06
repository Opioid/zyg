const Photon = @import("photon.zig").Photon;
const Map = @import("photon_map.zig").Map;
const Vertex = @import("../../../../scene/vertex.zig").Vertex;
const MaterialSample = @import("../../../../scene/material/sample.zig").Sample;
const Worker = @import("../../../worker.zig").Worker;
const Camera = @import("../../../../camera/perspective.zig").Perspective;
const Intersection = @import("../../../../scene/shape/intersection.zig").Intersection;
const InterfaceStack = @import("../../../../scene/prop/interface.zig").Stack;
const SampleFrom = @import("../../../../scene/shape/sample.zig").From;
const ro = @import("../../../../scene/ray_offset.zig");
const mat = @import("../../../../scene/material/material_helper.zig");
const Sampler = @import("../../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const AABB = math.AABB;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Mapper = struct {
    pub const Settings = struct {
        max_bounces: u32 = 0,
        full_light_path: bool = false,
    };

    settings: Settings = .{},
    sampler: Sampler = undefined,

    photons: []Photon = &.{},

    const Self = @This();

    pub fn configure(self: *Self, alloc: Allocator, settings: Settings, rng: *RNG) !void {
        self.settings = settings;
        self.sampler = .{ .Random = .{ .rng = rng } };
        self.photons = try alloc.realloc(self.photons, settings.max_bounces);
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.photons);
    }

    pub fn bake(
        self: *Self,
        map: *Map,
        begin: u32,
        end: u32,
        frame: u32,
        iteration: u32,
        worker: *Worker,
    ) u32 {
        _ = iteration;

        const world_bounds = if (self.settings.full_light_path) worker.scene.aabb() else worker.scene.causticAabb();
        const bounds = world_bounds;

        const finite = worker.scene.finite();

        var num_paths: u32 = 0;

        var i = begin;
        while (i < end) {
            const max_photons = @min(self.settings.max_bounces, end - i);
            const result = self.tracePhoton(bounds, frame, max_photons, finite, worker);

            if (result.num_iterations > 0) {
                for (self.photons[0..result.num_photons], 0..) |p, j| {
                    map.insert(p, i + j);
                }

                i += result.num_photons;
                num_paths += result.num_iterations;
            } else {
                return 0;
            }
        }

        return num_paths;
    }

    const Result = struct {
        num_iterations: u32,
        num_photons: u32,
    };

    fn tracePhoton(self: *Self, bounds: AABB, frame: u32, max_photons: u32, finite_world: bool, worker: *Worker) Result {
        // How often should we try to create a valid photon path?
        const Max_iterations = 1024 * 10;

        var iteration: u32 = 0;
        var num_photons: u32 = 0;

        var i: u32 = 0;
        while (i < Max_iterations) : (i += 1) {
            var caustic_path = false;

            var light_id: u32 = undefined;
            var light_sample: SampleFrom = undefined;
            var vertex = self.generateLightVertex(
                frame,
                bounds,
                worker,
                &light_id,
                &light_sample,
            ) orelse continue;

            const light = worker.scene.light(light_id);

            worker.interface_stack.clear();
            if (light.volumetric()) {
                worker.interface_stack.pushVolumeLight(light);
            }

            // if (!worker.interface_stack.empty()) {
            //     const vr = worker.volume(&ray, throughput, &isec, null, &self.sampler);
            //     throughput = vr.tr;

            //     if (.Abort == vr.event or .Absorb == vr.event) {
            //         continue;
            //     }
            // } else if (!worker.intersectAndResolveMask(&ray, null, &isec)) {
            //     continue;
            // }

            if (!worker.nextEvent(&vertex, @splat(1.0), &self.sampler)) {
                continue;
            }

            if (.Absorb == vertex.isec.event) {
                continue;
            }

            var throughput = vertex.isec.vol_tr;

            var radiance = light.evaluateFrom(vertex.isec.p, light_sample, &self.sampler, worker.scene) / @as(Vec4f, @splat(light_sample.pdf()));
            radiance *= throughput;

            while (vertex.depth < self.settings.max_bounces) {
                const wo = -vertex.ray.direction;

                const mat_sample = vertex.sample(&self.sampler, .Full, worker);

                if (mat_sample.isPureEmissive()) {
                    break;
                }

                const sample_result = mat_sample.sample(&self.sampler);
                if (0.0 == sample_result.pdf) {
                    break;
                }

                if (!sample_result.class.straight) {
                    if (!sample_result.class.specular and
                        (vertex.isec.subsurface() or mat_sample.super().sameHemisphere(wo)) and
                        (caustic_path or self.settings.full_light_path))
                    {
                        if (finite_world or bounds.pointInside(vertex.isec.p)) {
                            var radi = radiance;

                            const material_ior = vertex.isec.material(worker.scene).ior();
                            if (vertex.isec.subsurface() and material_ior > 1.0) {
                                const ior_t = worker.interface_stack.nextToBottomIor(worker.scene);
                                const eta = material_ior / ior_t;
                                radi *= @as(Vec4f, @splat(eta * eta));
                            }

                            self.photons[num_photons] = Photon{
                                .p = vertex.isec.p,
                                .wi = wo,
                                .alpha = .{ radi[0], radi[1], radi[2] },
                                .volumetric = vertex.isec.subsurface(),
                            };

                            iteration = i + 1;
                            num_photons += 1;

                            if (max_photons == num_photons) {
                                return .{ .num_iterations = iteration, .num_photons = num_photons };
                            }
                        }
                    }

                    if (sample_result.class.specular) {
                        caustic_path = true;
                    }

                    const nr = radiance * sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

                    const avg = math.average3(nr) / math.max(math.average3(radiance), 0.000001);
                    const continue_prob = math.min(1.0, avg);

                    if (self.sampler.sample1D() >= continue_prob) {
                        break;
                    }

                    radiance = nr / @as(Vec4f, @splat(continue_prob));
                }

                vertex.depth += 1;

                if (sample_result.class.straight) {
                    vertex.ray.setMinMaxT(ro.offsetF(vertex.ray.maxT()), ro.Ray_max_t);
                } else {
                    vertex.ray.origin = vertex.isec.offsetP(sample_result.wi);
                    vertex.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                    vertex.state.from_subsurface = vertex.isec.subsurface();
                }

                if (0.0 == vertex.wavelength) {
                    vertex.wavelength = sample_result.wavelength;
                }

                if (sample_result.class.transmission) {
                    const ior = worker.interfaceChangeIor(sample_result.wi, vertex.isec, &self.sampler);
                    const eta = ior.eta_i / ior.eta_t;
                    radiance *= @as(Vec4f, @splat(eta * eta));
                }

                if (!worker.nextEvent(&vertex, throughput, &self.sampler)) {
                    break;
                }

                if (.Absorb == vertex.isec.event) {
                    break;
                }

                throughput *= vertex.isec.vol_tr;

                self.sampler.incrementPadding();
            }

            if (iteration > 0) {
                return .{ .num_iterations = iteration, .num_photons = num_photons };
            }

            self.sampler.incrementSample();
        }

        return .{ .num_iterations = 0, .num_photons = 0 };
    }

    fn generateLightVertex(
        self: *Self,
        frame: u32,
        bounds: AABB,
        worker: *Worker,
        light_id: *u32,
        light_sample: *SampleFrom,
    ) ?Vertex {
        const select = self.sampler.sample1D();
        const l = worker.scene.randomLight(select);

        const time = worker.absoluteTime(frame, self.sampler.sample1D());

        const light = worker.scene.light(l.offset);
        light_sample.* = light.sampleFrom(time, &self.sampler, bounds, worker.scene) orelse return null;
        light_sample.mulAssignPdf(l.pdf);

        light_id.* = l.offset;

        return Vertex.init(light_sample.p, light_sample.dir, 0.0, ro.Ray_max_t, 0, 0.0, time, undefined);
    }
};
