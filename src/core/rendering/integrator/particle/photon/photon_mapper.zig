const Photon = @import("photon.zig").Photon;
const Map = @import("photon_map.zig").Map;
const Vertex = @import("../../../../scene/vertex.zig").Vertex;
const bxdf = @import("../../../../scene/material/bxdf.zig");
const Worker = @import("../../../worker.zig").Worker;
const Camera = @import("../../../../camera/perspective.zig").Perspective;
const SampleFrom = @import("../../../../scene/shape/sample.zig").From;
const Intersection = @import("../../../../scene/shape/intersection.zig").Intersection;
const ro = @import("../../../../scene/ray_offset.zig");
const hlp = @import("../../helper.zig");
const mat = @import("../../../../scene/material/material_helper.zig");
const Sampler = @import("../../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Ray = math.Ray;
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
            if (light.volumetric()) {
                vertex.interfaces.pushVolumeLight(light);
            }

            while (vertex.probe.depth.surface <= self.settings.max_bounces) {
                var sampler = &self.sampler;

                var isec: Intersection = undefined;
                if (!worker.nextEvent(true, &vertex, &isec, sampler)) {
                    break;
                }

                if (.Absorb == isec.event) {
                    break;
                }

                if (0 == vertex.probe.depth.surface) {
                    const pdf: Vec4f = @splat(light_sample.pdf());
                    const energy = light.evaluateFrom(isec.p, light_sample, sampler, worker.scene) / pdf;
                    vertex.throughput *= energy;
                    vertex.throughput_old = vertex.throughput;
                }

                const mat_sample = vertex.sample(&isec, &self.sampler, .Full, worker);

                if (mat_sample.canEvaluate() and (vertex.state.started_specular or self.settings.full_light_path)) {
                    if (finite_world or bounds.pointInside(isec.p)) {
                        var radiance = vertex.throughput;

                        const material_ior = isec.material(worker.scene).ior();
                        if (isec.subsurface() and material_ior > 1.0) {
                            const ior_t = vertex.interfaces.surroundingIor(worker.scene);
                            const eta = material_ior / ior_t;
                            radiance *= @as(Vec4f, @splat(eta * eta));
                        }

                        self.photons[num_photons] = Photon{
                            .p = isec.p,
                            .wi = -vertex.probe.ray.direction,
                            .alpha = .{ radiance[0], radiance[1], radiance[2] },
                            .volumetric = isec.subsurface(),
                        };

                        iteration = i + 1;
                        num_photons += 1;

                        if (max_photons == num_photons) {
                            return .{ .num_iterations = iteration, .num_photons = num_photons };
                        }
                    }
                }

                var bxdf_samples: bxdf.Samples = undefined;
                const sample_results = mat_sample.sample(sampler, false, &bxdf_samples);
                if (0 == sample_results.len) {
                    break;
                }

                const sample_result = sample_results[0];

                const class = sample_result.class;

                vertex.throughput_old = vertex.throughput;
                vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

                const rr = hlp.russianRoulette(vertex.throughput, vertex.throughput_old, sampler.sample1D()) orelse break;
                vertex.throughput /= @splat(rr);

                if (class.specular) {
                    vertex.state.treat_as_singular = true;

                    if (vertex.state.primary_ray) {
                        vertex.state.started_specular = true;
                    }
                } else if (!class.straight) {
                    vertex.state.treat_as_singular = false;
                    vertex.state.primary_ray = false;
                }

                vertex.probe.ray.origin = isec.offsetP(sample_result.wi);
                vertex.probe.ray.setDirection(sample_result.wi, ro.Ray_max_t);
                vertex.probe.depth.increment(&isec);

                if (!sample_result.class.straight) {
                    vertex.state.from_subsurface = isec.subsurface();
                    vertex.origin = isec.p;
                }

                if (0.0 == vertex.probe.wavelength) {
                    vertex.probe.wavelength = sample_result.wavelength;
                }

                if (class.transmission) {
                    const ior = vertex.interfaceChangeIor(&isec, sample_result.wi, &self.sampler, worker.scene);
                    const eta = ior.eta_i / ior.eta_t;
                    vertex.throughput *= @as(Vec4f, @splat(eta * eta));
                }

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

        return Vertex.init(Ray.init(light_sample.p, light_sample.dir, 0.0, ro.Ray_max_t), time, &.{});
    }
};
