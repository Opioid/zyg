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
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Lighttracer = struct {
    pub const Settings = struct {
        num_samples: u32,
        min_bounces: u32,
        max_bounces: u32,
        full_light_path: bool,
    };

    settings: Settings,

    light_sampler: Sampler = Sampler{ .Sobol = .{} },
    samplers: [2]Sampler = [2]Sampler{ .{ .Sobol = .{} }, .{ .Random = {} } },

    const Self = @This();

    pub fn startPixel(self: *Self, sample: u32, seed: u32) void {
        self.light_sampler.startPixel(sample, seed);

        for (self.samplers) |*s| {
            s.startPixel(sample, seed + 1);
        }
    }

    pub fn li(
        self: *Self,
        frame: u32,
        worker: *Worker,
        initial_stack: InterfaceStack,
    ) void {
        _ = initial_stack;

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

        const initrad = light.evaluateFrom(light_sample, Filter.Nearest, worker.super.scene) / @splat(4, light_sample.pdf());
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

            for (self.samplers) |*s| {
                s.incrementSample();
            }
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
                ray,
                wo,
                wo1,
                isec,
                filter,
                0.0,
                avoid_caustics,
                from_subsurface,
            );

            wo1 = wo;

            if (mat_sample.isPureEmissive()) {
                break;
            }

            var sampler = self.pickSampler(ray.depth);

            const sample_result = mat_sample.sample(sampler, &worker.super.rng);
            if (0.0 == sample_result.pdf) {
                break;
            }

            if (sample_result.class.straight) {
                ray.ray.setMinT(ro.offsetF(ray.ray.maxT()));

                if (!sample_result.class.transmission) {
                    ray.depth += 1;
                }
            } else {
                ray.ray.origin = isec.offsetP(sample_result.wi);
                ray.ray.setDirection(sample_result.wi);
                ray.depth += 1;

                if (!sample_result.class.specular and
                    (isec.subsurface or mat_sample.super().sameHemisphere(wo)) and
                    (caustic_path or self.settings.full_light_path))
                {
                    _ = directCamera(camera, radiance, ray, isec, mat_sample, filter, sampler, worker);
                }

                if (sample_result.class.specular) {
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

            if (sample_result.class.transmission) {
                const ior = worker.super.interfaceChangeIor(sample_result.wi, isec);
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

            sampler.incrementPadding();
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
        var sampler = &self.light_sampler;
        const s2 = sampler.sample2D(&worker.super.rng);
        const l = worker.super.scene.randomLight(s2[0]);
        const time = worker.super.absoluteTime(frame, s2[1]);

        const light = worker.super.scene.light(l.offset);
        light_sample.* = light.sampleFrom(time, sampler, bounds, &worker.super) orelse return null;
        light_sample.mulAssignPdf(l.pdf);

        light_id.* = l.offset;

        sampler.incrementSample();

        return Ray.init(light_sample.p, light_sample.dir, 0.0, scn.Ray_max_t, 0, 0.0, time);
    }

    fn directCamera(
        camera: *Camera,
        radiance: Vec4f,
        history: *const Ray,
        isec: *const Intersection,
        mat_sample: MaterialSample,
        filter: ?Filter,
        sampler: *Sampler,
        worker: *Worker,
    ) bool {
        if (!isec.visibleInCamera(worker.super.scene)) {
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
            sampler,
            &worker.super.rng,
            worker.super.scene,
        ) orelse return false;

        const wi = -camera_sample.dir;
        var ray = Ray.init(p, wi, p[3], camera_sample.t, history.depth, history.wavelength, history.time);

        const wo = mat_sample.super().wo;
        const tr = worker.transmitted(&ray, wo, isec, filter) orelse return false;

        const bxdf = mat_sample.evaluate(wi);

        const n = mat_sample.super().interpolatedNormal();
        var nsc = mat.nonSymmetryCompensation(wi, wo, isec.geo.geo_n, n);

        const material_ior = isec.material(worker.super.scene).ior();
        if (isec.subsurface and material_ior > 1.0) {
            const ior_t = worker.super.interface_stack.nextToBottomIor(worker.super.scene);
            const eta = material_ior / ior_t;
            nsc *= eta * eta;
        }

        const result = @splat(4, camera_sample.pdf * nsc) * (tr * radiance * bxdf.reflection);

        var crop = camera.crop;
        crop[2] -= crop[0] + 1;
        crop[3] -= crop[1] + 1;

        sensor.splatSample(camera_sample, result, crop);

        return true;
    }

    fn pickSampler(self: *Self, bounce: u32) *Sampler {
        if (bounce < 4) {
            return &self.samplers[0];
        }

        return &self.samplers[1];
    }
};

pub const Factory = struct {
    settings: Lighttracer.Settings,

    pub fn create(self: Factory) Lighttracer {
        return .{ .settings = self.settings };
    }
};
