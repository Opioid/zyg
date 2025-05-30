const Photon = @import("photon.zig").Photon;
const Map = @import("photon_map.zig").Map;
const Vertex = @import("../../../../scene/vertex.zig").Vertex;
const bxdf = @import("../../../../scene/material/bxdf.zig");
const Camera = @import("../../../../camera/camera_perspective.zig").Perspective;
const Context = @import("../../../../scene/context.zig").Context;
const SampleFrom = @import("../../../../scene/shape/sample.zig").From;
const Fragment = @import("../../../../scene/shape/intersection.zig").Fragment;
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

    pub fn bake(self: *Self, map: *Map, begin: u32, end: u32, frame: u32, iteration: u32, context: Context) u32 {
        _ = iteration;

        const world_bounds = if (self.settings.full_light_path) context.scene.aabb() else context.scene.causticAabb();
        const bounds = world_bounds;

        const finite = context.scene.finite();

        var num_paths: u32 = 0;

        var i = begin;
        while (i < end) {
            const max_photons = @min(self.settings.max_bounces, end - i);
            const result = self.tracePhoton(bounds, frame, max_photons, finite, context);

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

    fn tracePhoton(self: *Self, bounds: AABB, frame: u32, max_photons: u32, finite_world: bool, context: Context) Result {
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
                context,
                &light_id,
                &light_sample,
            ) orelse continue;

            const light = context.scene.light(light_id);

            while (vertex.probe.depth.surface <= self.settings.max_bounces) {
                var sampler = &self.sampler;

                var frag: Fragment = undefined;
                context.nextEvent(&vertex, &frag, sampler);
                if (.Absorb == frag.event or .Abort == frag.event or !frag.hit()) {
                    break;
                }

                if (0 == vertex.probe.depth.surface) {
                    const pdf: Vec4f = @splat(light_sample.pdf());
                    const energy = light.evaluateFrom(frag.p, light_sample, sampler, context) / pdf;
                    vertex.throughput *= energy;
                }

                const mat_sample = vertex.sample(&frag, &self.sampler, .Full, context);

                if (mat_sample.canEvaluate() and (vertex.state.started_specular or self.settings.full_light_path)) {
                    if (finite_world or bounds.pointInside(frag.p)) {
                        var radiance = vertex.throughput;

                        const material_ior = frag.material(context.scene).ior();
                        if (frag.subsurface() and material_ior > 1.0) {
                            const ior_t = vertex.mediums.surroundingIor();
                            const eta = material_ior / ior_t;
                            radiance *= @as(Vec4f, @splat(eta * eta));
                        }

                        self.photons[num_photons] = Photon{
                            .p = frag.p,
                            .wi = -vertex.probe.ray.direction,
                            .alpha = .{ radiance[0], radiance[1], radiance[2] },
                            .volumetric = frag.subsurface(),
                        };

                        iteration = i + 1;
                        num_photons += 1;

                        if (max_photons == num_photons) {
                            return .{ .num_iterations = iteration, .num_photons = num_photons };
                        }
                    }
                }

                var bxdf_samples: bxdf.Samples = undefined;
                const sample_results = mat_sample.sample(sampler, 1, &bxdf_samples);
                if (0 == sample_results.len) {
                    break;
                }

                const sample_result = sample_results[0];

                const class = sample_result.class;

                vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

                if (hlp.russianRoulette(&vertex.throughput, sampler.sample1D())) {
                    break;
                }

                if (class.specular) {
                    vertex.state.treat_as_singular = true;

                    if (vertex.state.primary_ray) {
                        vertex.state.started_specular = true;
                    }
                } else if (!class.straight) {
                    vertex.state.treat_as_singular = false;
                    vertex.state.primary_ray = false;
                }

                vertex.probe.ray = frag.offsetRay(sample_result.wi, ro.RayMaxT);
                vertex.probe.depth.increment(&frag);

                if (!sample_result.class.straight) {
                    vertex.origin = frag.p;
                }

                if (0.0 == vertex.probe.wavelength) {
                    vertex.probe.wavelength = sample_result.wavelength;
                }

                if (class.transmission) {
                    const ior = vertex.interfaceChangeIor(sample_result.wi, &frag, &mat_sample, context.scene);
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
        context: Context,
        light_id: *u32,
        light_sample: *SampleFrom,
    ) ?Vertex {
        const select = self.sampler.sample1D();
        const l = context.scene.randomLight(select);

        const time = context.absoluteTime(frame, self.sampler.sample1D());

        const light = context.scene.light(l.offset);
        light_sample.* = light.sampleFrom(time, &self.sampler, bounds, context.scene) orelse return null;
        light_sample.mulAssignPdf(l.pdf);

        light_id.* = l.offset;

        return Vertex.init(Ray.init(light_sample.p, light_sample.dir, 0.0, ro.RayMaxT), time);
    }
};
