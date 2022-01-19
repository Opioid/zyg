const Ray = @import("../../../scene/ray.zig").Ray;
const MaterialSample = @import("../../../scene/material/sample.zig").Sample;
const Worker = @import("../../worker.zig").Worker;
const Camera = @import("../../../camera/perspective.zig").Perspective;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const SampleFrom = @import("../../../scene/shape/sample.zig").From;
const Filter = @import("../../../image/texture/sampler.zig").Filter;
const scn = @import("../../../scene/constants.zig");
const ro = @import("../../../scene/ray_offset.zig");
const mat = @import("../../../scene/material/material_helper.zig");
const smp = @import("../../../sampler/sampler.zig");

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Lighttracer = struct {
    const Num_dedicated_samplers = 3;

    pub const Settings = struct {
        num_samples: u32,
        min_bounces: u32,
        max_bounces: u32,
        full_light_path: bool,
    };

    settings: Settings,

    samplers: [Num_dedicated_samplers]smp.Sampler,
    sampler: smp.Sampler,
    light_sampler: smp.Sampler,

    const Self = @This();

    pub fn init(alloc: Allocator, settings: Settings) !Self {
        const num_samples = settings.num_samples;

        if (num_samples <= 1) {
            return Self{
                .settings = settings,
                .samplers = .{
                    .{ .Random = .{} },
                    .{ .Random = .{} },
                    .{ .Random = .{} },
                },
                .sampler = .{ .Random = .{} },
                .light_sampler = .{ .Random = .{} },
            };
        } else {
            return Self{
                .settings = settings,
                .samplers = .{
                    .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, 1, 2, num_samples) },
                    .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, 1, 2, num_samples) },
                    .{ .GoldenRatio = try smp.GoldenRatio.init(alloc, 1, 2, num_samples) },
                },
                .sampler = .{ .Random = .{} },
                .light_sampler = .{ .Random = .{} },
            };
        }
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        for (self.samplers) |*s| {
            s.deinit(alloc);
        }

        self.sampler.deinit(alloc);
        self.light_sampler.deinit(alloc);
    }

    pub fn startPixel(self: *Self) void {
        self.sampler.startPixel();
        self.light_sampler.startPixel();
    }

    pub fn li(
        self: *Self,
        frame: u32,
        worker: *Worker,
        initial_stack: InterfaceStack,
    ) void {
        _ = initial_stack;

        for (self.samplers) |*s| {
            s.startPixel();
        }

        const world_bounds = if (self.settings.full_light_path) worker.super.scene.aabb() else worker.super.scene.causticAabb();
        const frustum_bounds = world_bounds;

        var light_id: u32 = undefined;
        var light_sample: SampleFrom = undefined;
        var ray = self.generateLightRay(
            frame,
            frustum_bounds,
            worker,
            &light_id,
            &light_sample,
        ) orelse return;

        const light = worker.super.scene.light(light_id);
        const volumetric = light.volumetric();

        worker.super.interface_stack.clear();
        if (volumetric) {
            worker.super.interface_stack.pushVolumeLight(light);
        }

        var throughput = @splat(4, @as(f32, 1.0));

        var isec = Intersection{};
        if (!worker.super.interface_stack.empty()) {
            const vr = worker.volume(&ray, &isec, null);
            throughput = vr.tr;

            if (.Abort == vr.event or .Absorb == vr.event) {
                return;
            }
        } else if (!worker.super.intersectAndResolveMask(&ray, null, &isec)) {
            return;
        }

        const initrad = light.evaluateFrom(light_sample, Filter.Nearest, worker.super) / @splat(4, light_sample.pdf());
        const radiance = throughput * initrad;

        var i = self.settings.num_samples;
        while (i > 0) : (i -= 1) {
            worker.super.interface_stack.clear();
            if (volumetric) {
                worker.super.interface_stack.pushVolumeLight(light);
            }

            var split_ray = ray;
            var split_isec = isec;

            self.integrate(radiance, &split_ray, &split_isec, worker, light_id, light_sample.xy);
        }
    }

    fn integrate(
        self: *Self,
        radiance_: Vec4f,
        ray: *Ray,
        isec: *Intersection,
        worker: *Worker,
        light_id: u32,
        light_sample_xy: Vec2f,
    ) void {
        const camera = worker.super.camera;

        var radiance = radiance_;

        const avoid_caustics = false;

        var caustic_path = false;
        var from_subsurface = false;

        var wo1 = @splat(4, @as(f32, 0.0));

        while (true) {
            const wo = -ray.ray.direction;

            const filter: ?Filter = if (ray.depth <= 1 or caustic_path) null else .Nearest;
            const mat_sample = worker.super.sampleMaterial(
                ray.*,
                wo,
                wo1,
                isec.*,
                filter,
                0.0,
                avoid_caustics,
                from_subsurface,
            );

            wo1 = wo;

            if (mat_sample.isPureEmissive()) {
                break;
            }

            const sample_result = mat_sample.sample(self.materialSampler(ray.depth), &worker.super.rng);
            if (0.0 == sample_result.pdf) {
                break;
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

                if (sample_result.typef.no(.Specular) and
                    (isec.subsurface or mat_sample.super().sameHemisphere(wo)) and
                    (caustic_path or self.settings.full_light_path))
                {
                    _ = self.directCamera(camera, radiance, ray.*, isec.*, mat_sample, filter, worker);
                }

                if (sample_result.typef.is(.Specular)) {
                    caustic_path = true;
                }

                from_subsurface = false;
            }

            if (ray.depth >= self.settings.max_bounces) {
                break;
            }

            ray.ray.setMaxT(scn.Ray_max_t);

            if (0.0 == ray.wavelength) {
                ray.wavelength = sample_result.wavelength;
            }

            radiance *= sample_result.reflection / @splat(4, sample_result.pdf);

            if (sample_result.typef.is(.Transmission)) {
                const ior = worker.super.interfaceChangeIor(sample_result.wi, isec.*);
                const eta = ior.eta_i / ior.eta_t;
                radiance *= @splat(4, eta * eta);
            }

            from_subsurface = from_subsurface or isec.subsurface;

            if (!worker.super.interface_stack.empty()) {
                const vr = worker.volume(ray, isec, filter);

                // result += throughput * vr.li;
                radiance *= vr.tr;

                if (.Abort == vr.event or .Absorb == vr.event) {
                    break;
                }
            } else if (!worker.super.intersectAndResolveMask(ray, filter, isec)) {
                break;
            }
        }

        _ = light_id;
        _ = light_sample_xy;
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
        const select = self.light_sampler.sample1D(rng, 0);
        const l = worker.super.scene.randomLight(select);

        const time = worker.super.absoluteTime(frame, self.light_sampler.sample1D(rng, 2));

        const light = worker.super.scene.light(l.offset);
        light_sample.* = light.sampleFrom(time, &self.light_sampler, 1, bounds, &worker.super) orelse return null;
        light_sample.mulAssignPdf(l.pdf);

        light_id.* = l.offset;

        return Ray.init(light_sample.p, light_sample.dir, 0.0, scn.Ray_max_t, 0, 0.0, time);
    }

    fn directCamera(
        self: *Self,
        camera: *Camera,
        radiance: Vec4f,
        history: Ray,
        isec: Intersection,
        mat_sample: MaterialSample,
        filter: ?Filter,
        worker: *Worker,
    ) bool {
        if (!isec.visibleInCamera(worker.super)) {
            return false;
        }

        var sensor = &camera.sensor;
        const fr = sensor.filterRadiusInt();

        var filter_crop = camera.crop + Vec4i{ -fr, -fr, fr, fr };
        filter_crop[2] -= filter_crop[0] + 1;
        filter_crop[3] -= filter_crop[1] + 1;

        const p = isec.offsetPN(mat_sample.super().geometricNormal(), mat_sample.isTranslucent());

        const camera_sample = camera.sampleTo(
            filter_crop,
            history.time,
            p,
            &self.sampler,
            &worker.super.rng,
            0,
            worker.super.scene.*,
        ) orelse return false;

        const wi = -camera_sample.dir;
        var ray = Ray.init(p, wi, p[3], camera_sample.t, history.depth, history.wavelength, history.time);

        const wo = mat_sample.super().wo;
        const tr = worker.transmitted(&ray, wo, isec, filter) orelse return false;

        const bxdf = mat_sample.evaluate(wi);

        const n = mat_sample.super().interpolatedNormal();
        var nsc = mat.nonSymmetryCompensation(wi, wo, isec.geo.geo_n, n);

        const material_ior = isec.material(worker.super).ior();
        if (isec.subsurface and material_ior > 1.0) {
            const ior_t = worker.super.interface_stack.nextToBottomIor(worker.super);
            const eta = material_ior / ior_t;
            nsc *= eta * eta;
        }

        const result = @splat(4, camera_sample.pdf * nsc) * (tr * radiance * bxdf.reflection);

        var crop = camera.crop;
        crop[2] -= crop[0] + 1;
        crop[3] -= crop[1] + 1;

        sensor.splatSample(camera_sample, result, .{ 0, 0 }, crop);

        return true;
    }

    fn materialSampler(self: *Self, bounce: u32) *smp.Sampler {
        if (Num_dedicated_samplers > bounce) {
            return &self.samplers[bounce];
        }

        return &self.sampler;
    }
};

pub const Factory = struct {
    settings: Lighttracer.Settings,

    pub fn create(self: Factory, alloc: Allocator) !Lighttracer {
        return try Lighttracer.init(alloc, self.settings);
    }
};
