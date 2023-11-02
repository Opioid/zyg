const Vertex = @import("../../../scene/vertex.zig").Vertex;
const MaterialSample = @import("../../../scene/material/sample.zig").Sample;
const bxdf = @import("../../../scene/material/bxdf.zig");
const Worker = @import("../../worker.zig").Worker;
const Camera = @import("../../../camera/perspective.zig").Perspective;
const Light = @import("../../../scene/light/light.zig").Light;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const SampleFrom = @import("../../../scene/shape/sample.zig").From;
const Intersection = @import("../../../scene/shape/intersection.zig").Intersection;
const ro = @import("../../../scene/ray_offset.zig");
const hlp = @import("../helper.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Ray = math.Ray;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Lighttracer = struct {
    pub const Settings = struct {
        min_bounces: u32,
        max_bounces: u32,
        full_light_path: bool,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: *Self, frame: u32, worker: *Worker, initial_stack: *const InterfaceStack) void {
        _ = initial_stack;

        const world_bounds = if (self.settings.full_light_path) worker.scene.aabb() else worker.scene.causticAabb();
        const frustum_bounds = world_bounds;

        var sampler = worker.pickSampler(0);

        var light_id: u32 = undefined;
        var light_sample: SampleFrom = undefined;
        var vertex = generateLightVertex(
            frame,
            frustum_bounds,
            sampler,
            worker,
            &light_id,
            &light_sample,
        ) orelse return;

        const light = worker.scene.light(light_id);
        const volumetric = light.volumetric();

        if (volumetric) {
            vertex.interfaces.pushVolumeLight(light);
        }

        self.integrate(&vertex, worker, light, light_sample);
    }

    fn integrate(self: *Self, vertex: *Vertex, worker: *Worker, light: Light, light_sample: SampleFrom) void {
        const camera = worker.camera;

        while (true) {
            var sampler = worker.pickSampler(vertex.probe.depth);

            var isec: Intersection = undefined;
            if (!worker.nextEvent(vertex, &isec, sampler)) {
                break;
            }

            if (vertex.probe.depth >= self.settings.max_bounces or .Absorb == isec.event) {
                break;
            }

            if (0 == vertex.probe.depth) {
                const radiance = light.evaluateFrom(isec.p, light_sample, sampler, worker.scene) / @as(Vec4f, @splat(light_sample.pdf()));
                vertex.throughput *= radiance;
                vertex.throughput_old = vertex.throughput;
            }

            const mat_sample = vertex.sample(&isec, sampler, .Full, worker);

            const wo = -vertex.probe.ray.direction;
            if (mat_sample.canEvaluate() and
                (isec.subsurface() or mat_sample.super().sameHemisphere(wo)) and
                (vertex.state.started_specular or self.settings.full_light_path))
            {
                _ = directCamera(camera, vertex, &isec, &mat_sample, sampler, worker);

                // const rr = hlp.russianRoulette(vertex.throughput, vertex.throughput_old, sampler.sample1D()) orelse break;
                // vertex.throughput /= @splat(rr);
            }

            var bxdf_samples: bxdf.Samples = undefined;
            const sample_results = mat_sample.sample(sampler, false, &bxdf_samples);
            if (0 == sample_results.len) {
                break;
            }

            const sample_result = sample_results[0];

            const class = sample_result.class;
            if (class.specular) {
                vertex.state.treat_as_singular = true;

                if (vertex.state.primary_ray) {
                    vertex.state.started_specular = true;
                }
            } else if (!class.straight) {
                if (!self.settings.full_light_path and !vertex.state.started_specular) {
                    break;
                }

                vertex.state.treat_as_singular = false;
                vertex.state.primary_ray = false;
            }

            if (class.straight) {
                vertex.probe.ray.setMinMaxT(ro.offsetF(vertex.probe.ray.maxT()), ro.Ray_max_t);
            } else {
                vertex.probe.ray.origin = isec.offsetP(sample_result.wi);
                vertex.probe.ray.setDirection(sample_result.wi, ro.Ray_max_t);

                vertex.state.from_subsurface = isec.subsurface();
            }

            vertex.probe.depth += 1;

            if (0.0 == vertex.probe.wavelength) {
                vertex.probe.wavelength = sample_result.wavelength;
            }

            vertex.throughput_old = vertex.throughput;
            vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

            if (sample_result.class.transmission) {
                const ior = vertex.interfaceChangeIor(&isec, sample_result.wi, sampler, worker.scene);
                const eta = ior.eta_i / ior.eta_t;
                vertex.throughput *= @as(Vec4f, @splat(eta * eta));
            }

            sampler.incrementPadding();
        }
    }

    fn generateLightVertex(
        frame: u32,
        bounds: AABB,
        sampler: *Sampler,
        worker: *Worker,
        light_id: *u32,
        light_sample: *SampleFrom,
    ) ?Vertex {
        const s2 = sampler.sample2D();
        const l = worker.scene.randomLight(s2[0]);
        const time = worker.absoluteTime(frame, s2[1]);

        const light = worker.scene.light(l.offset);
        light_sample.* = light.sampleFrom(time, sampler, bounds, worker.scene) orelse return null;
        light_sample.mulAssignPdf(l.pdf);

        light_id.* = l.offset;

        sampler.incrementPadding();

        return Vertex.init(Ray.init(light_sample.p, light_sample.dir, 0.0, ro.Ray_max_t), time, &.{});
    }

    fn directCamera(
        camera: *Camera,
        vertex: *const Vertex,
        isec: *const Intersection,
        mat_sample: *const MaterialSample,
        sampler: *Sampler,
        worker: *Worker,
    ) bool {
        if (!isec.visibleInCamera(worker.scene)) {
            return false;
        }

        var sensor = &camera.sensor;
        const fr = sensor.filter_radius_int;

        var filter_crop = camera.crop + Vec4i{ -fr, -fr, fr, fr };

        filter_crop[2] -= filter_crop[0] + 1;
        filter_crop[3] -= filter_crop[1] + 1;

        const trafo = worker.scene.propTransformationAt(camera.entity, vertex.probe.time);
        const p = isec.offsetP(math.normalize3(trafo.position - isec.p));

        const camera_sample = camera.sampleTo(
            filter_crop,
            vertex.probe.time,
            p,
            sampler,
            worker.scene,
        ) orelse return false;

        const wi = -camera_sample.dir;
        var tprobe = vertex.probe.clone(Ray.init(p, wi, p[3], camera_sample.t));

        const tr = worker.visibility(&tprobe, isec, &vertex.interfaces, sampler) orelse return false;

        const bxdf_result = mat_sample.evaluate(wi, false);

        const wo = mat_sample.super().wo;
        const n = mat_sample.super().interpolatedNormal();
        var nsc = hlp.nonSymmetryCompensation(wi, wo, isec.geo_n, n);

        const material_ior = isec.material(worker.scene).ior();
        if (isec.subsurface() and material_ior > 1.0) {
            const ior_t = vertex.interfaces.nextToBottomIor(worker.scene);
            const eta = material_ior / ior_t;
            nsc *= eta * eta;
        }

        const result = @as(Vec4f, @splat(camera_sample.pdf * nsc)) * (tr * vertex.throughput * bxdf_result.reflection);

        var crop = camera.crop;
        crop[2] -= crop[0] + 1;
        crop[3] -= crop[1] + 1;

        sensor.splatSample(camera_sample, result, crop);

        return true;
    }
};

pub const Factory = struct {
    settings: Lighttracer.Settings,

    pub fn create(self: Factory) Lighttracer {
        return .{ .settings = self.settings };
    }
};
