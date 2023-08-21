const Vertex = @import("../../../scene/vertex.zig").Vertex;
const MaterialSample = @import("../../../scene/material/sample.zig").Sample;
const Worker = @import("../../worker.zig").Worker;
const Camera = @import("../../../camera/perspective.zig").Perspective;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;
const SampleFrom = @import("../../../scene/shape/sample.zig").From;
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

        worker.interface_stack.clear();
        if (volumetric) {
            worker.interface_stack.pushVolumeLight(light);
        }

        var isec = Intersection{};

        if (!worker.nextEvent(&vertex, @splat(1.0), &isec, sampler)) {
            return;
        }

        if (.Absorb == isec.volume.event) {
            return;
        }

        sampler.incrementPadding();

        const throughput = isec.volume.tr;

        const initrad = light.evaluateFrom(isec.geo.p, light_sample, sampler, worker.scene) / @as(Vec4f, @splat(light_sample.pdf()));
        const radiance = throughput * initrad;

        worker.interface_stack.clear();
        if (volumetric) {
            worker.interface_stack.pushVolumeLight(light);
        }

        var split_vertex = vertex;
        var split_isec = isec;

        self.integrate(radiance, &split_vertex, &split_isec, worker, light_id, light_sample.xy);
    }

    fn integrate(
        self: *Self,
        radiance_: Vec4f,
        vertex: *Vertex,
        isec: *Intersection,
        worker: *Worker,
        light_id: u32,
        light_sample_xy: Vec2f,
    ) void {
        const camera = worker.camera;

        var radiance = radiance_;
        var caustic_path = false;

        while (true) {
            const wo = -vertex.ray.direction;

            var sampler = worker.pickSampler(vertex.depth);
            const mat_sample = worker.sampleMaterial(
                vertex.*,
                isec.*,
                sampler,
                0.0,
                .Full,
            );

            if (mat_sample.isPureEmissive()) {
                break;
            }

            const sample_result = mat_sample.sample(sampler);
            if (0.0 == sample_result.pdf) {
                break;
            }

            if (sample_result.class.straight) {
                vertex.ray.setMinMaxT(ro.offsetF(vertex.ray.maxT()), ro.Ray_max_t);

                if (!sample_result.class.transmission) {
                    vertex.depth += 1;
                }
            } else {
                vertex.ray.origin = isec.offsetP(sample_result.wi);
                vertex.ray.setDirection(sample_result.wi, ro.Ray_max_t);
                vertex.depth += 1;

                if (!sample_result.class.specular and
                    (isec.subsurface() or mat_sample.super().sameHemisphere(wo)) and
                    (caustic_path or self.settings.full_light_path))
                {
                    _ = directCamera(camera, radiance, vertex.*, isec.*, &mat_sample, sampler, worker);
                }

                if (sample_result.class.specular) {
                    caustic_path = true;
                }

                vertex.state.from_subsurface = isec.subsurface();
            }

            if (vertex.depth >= self.settings.max_bounces) {
                break;
            }

            if (0.0 == vertex.wavelength) {
                vertex.wavelength = sample_result.wavelength;
            }

            radiance *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

            if (sample_result.class.transmission) {
                const ior = worker.interfaceChangeIor(sample_result.wi, isec.*, sampler);
                const eta = ior.eta_i / ior.eta_t;
                radiance *= @as(Vec4f, @splat(eta * eta));
            }

            if (!worker.nextEvent(vertex, @splat(1.0), isec, sampler)) {
                break;
            }

            radiance *= isec.volume.tr;

            if (.Absorb == isec.volume.event) {
                break;
            }

            sampler.incrementPadding();
        }

        _ = light_id;
        _ = light_sample_xy;
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

        return Vertex.init(light_sample.p, light_sample.dir, 0.0, ro.Ray_max_t, 0, 0.0, time);
    }

    fn directCamera(
        camera: *Camera,
        radiance: Vec4f,
        history: Vertex,
        isec: Intersection,
        mat_sample: *const MaterialSample,
        sampler: *Sampler,
        worker: *Worker,
    ) bool {
        if (!isec.visibleInCamera(worker.scene)) {
            return false;
        }

        var sensor = &camera.sensor;
        const fr = sensor.filterRadiusInt();

        var filter_crop = camera.crop + Vec4i{ -fr, -fr, fr, fr };
        filter_crop[2] -= filter_crop[0] + 1;
        filter_crop[3] -= filter_crop[1] + 1;

        const trafo = worker.scene.propTransformationAt(camera.entity, history.time);
        const p = isec.offsetP(math.normalize3(trafo.position - isec.geo.p));

        const camera_sample = camera.sampleTo(
            filter_crop,
            history.time,
            p,
            sampler,
            worker.scene,
        ) orelse return false;

        const wi = -camera_sample.dir;
        var vertex = Vertex.init(p, wi, p[3], camera_sample.t, history.depth, history.wavelength, history.time);

        const wo = mat_sample.super().wo;
        const tr = worker.visibility(&vertex, isec, sampler) orelse return false;

        const bxdf = mat_sample.evaluate(wi);

        const n = mat_sample.super().interpolatedNormal();
        var nsc = mat.nonSymmetryCompensation(wi, wo, isec.geo.geo_n, n);

        const material_ior = isec.material(worker.scene).ior();
        if (isec.subsurface() and material_ior > 1.0) {
            const ior_t = worker.interface_stack.nextToBottomIor(worker.scene);
            const eta = material_ior / ior_t;
            nsc *= eta * eta;
        }

        const result = @as(Vec4f, @splat(camera_sample.pdf * nsc)) * (tr * radiance * bxdf.reflection);

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
