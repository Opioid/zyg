const Photon = @import("photon.zig").Photon;
const Map = @import("photon_map.zig").Map;
const Ray = @import("../../../../scene/ray.zig").Ray;
const MaterialSample = @import("../../../../scene/material/sample.zig").Sample;
const Worker = @import("../../../worker.zig").Worker;
const Camera = @import("../../../../camera/perspective.zig").Perspective;
const Intersection = @import("../../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../../scene/prop/interface.zig").Stack;
const SampleFrom = @import("../../../../scene/shape/sample.zig").From;
const Filter = @import("../../../../image/texture/sampler.zig").Filter;
const scn = @import("../../../../scene/constants.zig");
const ro = @import("../../../../scene/ray_offset.zig");
const mat = @import("../../../../scene/material/material_helper.zig");
const smp = @import("../../../../sampler/sampler.zig");

const base = @import("base");
const math = base.math;
const AABB = math.AABB;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Mapper = struct {
    pub const Settings = struct {
        max_bounces: u32,
        full_light_path: bool,
    };

    settings: Settings,
    sampler: smp.Sampler,

    photons: [*]Photon,

    const Self = @This();

    pub fn init(alloc: Allocator, settings: Settings) !Self {
        return Self{
            .settings = settings,
            .sampler = .{ .Random = .{} },
            .photons = (try alloc.alloc(Photon, settings.max_bounces)).ptr,
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.photons[0..self.settings.max_bounces]);
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

        const world_bounds = if (self.settings.full_light_path) worker.super.scene.aabb() else worker.super.scene.causticAabb();
        const bounds = world_bounds;

        const is_finite = worker.super.scene.isFinite();

        var num_paths: u32 = 0;

        var i = begin;
        while (i < end) {
            const max_photons = std.math.min(self.settings.max_bounces, end - i);
            const result = self.tracePhoton(bounds, frame, max_photons, is_finite, worker);

            if (result.num_iterations > 0) {
                for (self.photons[0..result.num_photons]) |p, j| {
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

        const Avoid_caustics = false;

        var unnatural_limit = bounds;
        unnatural_limit.scale(8.0);

        var iteration: u32 = 0;
        var num_photons: u32 = 0;

        var i: u32 = 0;
        while (i < Max_iterations) : (i += 1) {
            worker.super.interface_stack.clear();

            var filter: ?Filter = null;

            var caustic_path = false;
            var from_subsurface = false;

            var light_id: u32 = undefined;
            var light_sample: SampleFrom = undefined;
            var ray = self.generateLightRay(
                frame,
                bounds,
                worker,
                &light_id,
                &light_sample,
            ) orelse continue;

            var isec = Intersection{};
            if (!worker.super.intersectAndResolveMask(&ray, filter, &isec)) {
                continue;
            }

            const light = worker.super.scene.light(light_id);

            var radiance = light.evaluateFrom(light_sample, Filter.Nearest, worker.super) / @splat(4, light_sample.pdf());

            var wo1 = @splat(4, @as(f32, 0.0));

            while (ray.depth < self.settings.max_bounces) {
                const wo = -ray.ray.direction;

                const mat_sample = worker.super.sampleMaterial(
                    ray,
                    wo,
                    wo1,
                    isec,
                    filter,
                    0.0,
                    Avoid_caustics,
                    from_subsurface,
                );

                wo1 = wo;

                if (mat_sample.isPureEmissive()) {
                    break;
                }

                const sample_result = mat_sample.sample(&self.sampler, &worker.super.rng);
                if (0.0 == sample_result.pdf) {
                    break;
                }

                if (sample_result.typef.no(.Straight)) {
                    if (sample_result.typef.no(.Specular) and
                        (isec.subsurface or mat_sample.super().sameHemisphere(wo)) and
                        (caustic_path or self.settings.full_light_path))
                    {
                        if (finite_world or unnatural_limit.pointInside(isec.geo.p)) {
                            var radi = radiance;

                            const material_ior = isec.material(worker.super).ior();
                            if (isec.subsurface and material_ior > 1.0) {
                                const ior_t = worker.super.interface_stack.nextToBottomIor(worker.super);
                                const eta = material_ior / ior_t;
                                radi *= @splat(4, eta * eta);
                            }

                            self.photons[num_photons] = Photon{
                                .p = isec.geo.p,
                                .wi = wo,
                                .alpha = .{ radi[0], radi[1], radi[2] },
                                .volumetric = isec.subsurface,
                            };

                            iteration = i + 1;
                            num_photons += 1;

                            if (max_photons == num_photons) {
                                return .{ .num_iterations = iteration, .num_photons = num_photons };
                            }
                        }
                    }

                    if (sample_result.typef.is(.Specular)) {
                        caustic_path = true;
                    } else {
                        filter = .Nearest;
                    }

                    const nr = radiance * sample_result.reflection / @splat(4, sample_result.pdf);
                    const avg = math.average3(nr) / math.average3(radiance);

                    const continue_prob = std.math.min(1.0, avg);

                    if (self.sampler.sample1D(&worker.super.rng, 0) > continue_prob) {
                        break;
                    }

                    radiance = nr / @splat(4, continue_prob);
                }

                if (sample_result.typef.is(.Straight)) {
                    ray.ray.setMinT(ro.offsetF(ray.ray.maxT()));

                    if (sample_result.typef.no(.Transmission)) {
                        ray.depth += 1;
                    }
                } else {
                    ray.ray.origin = isec.offsetP(sample_result.wi);
                    ray.ray.setDirection(sample_result.wi);
                    ray.depth += 1;

                    from_subsurface = false;
                }

                ray.ray.setMaxT(scn.Ray_max_t);

                if (0.0 == ray.wavelength) {
                    ray.wavelength = sample_result.wavelength;
                }

                if (sample_result.typef.is(.Transmission)) {
                    const ior = worker.super.interfaceChangeIor(sample_result.wi, isec);
                    const eta = ior.eta_i / ior.eta_t;
                    radiance *= @splat(4, eta * eta);
                }

                from_subsurface = from_subsurface or isec.subsurface;

                if (!worker.super.interface_stack.empty()) {
                    const vr = worker.volume(&ray, &isec, filter);

                    // result += throughput * vr.li;
                    radiance *= vr.tr;

                    if (.Abort == vr.event or .Absorb == vr.event) {
                        break;
                    }
                } else if (!worker.super.intersectAndResolveMask(&ray, filter, &isec)) {
                    break;
                }
            }

            if (iteration > 0) {
                return .{ .num_iterations = iteration, .num_photons = num_photons };
            }
        }

        return .{ .num_iterations = 0, .num_photons = 0 };
    }

    fn generateLightRay(
        self: *Self,
        frame: u32,
        bounds: AABB,
        worker: *Worker,
        light_id: *u32,
        light_sample: *SampleFrom,
    ) ?Ray {
        var rng = &worker.super.rng;
        const select = self.sampler.sample1D(rng, 0);
        const l = worker.super.scene.randomLight(select);

        const time = worker.super.absoluteTime(frame, self.sampler.sample1D(rng, 2));

        const light = worker.super.scene.light(l.offset);
        light_sample.* = light.sampleFrom(time, &self.sampler, 1, bounds, &worker.super) orelse return null;
        light_sample.mulAssignPdf(l.pdf);

        light_id.* = l.offset;

        return Ray.init(light_sample.p, light_sample.dir, 0.0, scn.Ray_max_t, 0, 0.0, time);
    }
};
