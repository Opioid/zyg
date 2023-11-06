const vt = @import("../../../scene/vertex.zig");
const Vertex = vt.Vertex;
const VertexPool = vt.Pool;
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
        if (light.volumetric()) {
            vertex.interfaces.pushVolumeLight(light);
        }

        self.integrate(vertex, worker, light, light_sample);
    }

    fn integrate(self: *Self, input: Vertex, worker: *Worker, light: Light, light_sample: SampleFrom) void {
        const camera = worker.camera;

        var vertices: VertexPool = .{};
        vertices.start(input);

        while (vertices.iterate()) {
            while (vertices.consume()) |vertex| {
                if (vertex.probe.depth >= self.settings.max_bounces) {
                    continue;
                }

                var sampler = worker.pickSampler(vertex.probe.depth);

                var isec: Intersection = undefined;
                if (!worker.nextEvent(true, vertex, &isec, sampler)) {
                    continue;
                }

                if (.Absorb == isec.event) {
                    continue;
                }

                if (0 == vertex.probe.depth) {
                    const pdf: Vec4f = @splat(light_sample.pdf());
                    const energy = light.evaluateFrom(isec.p, light_sample, sampler, worker.scene) / pdf;
                    vertex.throughput *= energy;
                    vertex.throughput_old = vertex.throughput;
                }

                const mat_sample = vertex.sample(&isec, sampler, .Full, worker);

                const split = vertex.path_count <= 2 and vertex.state.primary_ray;

                if (mat_sample.canEvaluate() and (vertex.state.started_specular or self.settings.full_light_path)) {
                    _ = directCamera(camera, vertex, &isec, &mat_sample, split, sampler, worker);

                    if (vertex.probe.depth >= self.settings.min_bounces) {
                        const rr = hlp.russianRoulette(vertex.throughput, vertex.throughput_old, sampler.sample1D()) orelse continue;
                        vertex.throughput /= @splat(rr);
                    }
                }

                var bxdf_samples: bxdf.Samples = undefined;
                const sample_results = mat_sample.sample(sampler, split, &bxdf_samples);
                const path_count: u32 = @intCast(sample_results.len);

                for (sample_results) |sample_result| {
                    const class = sample_result.class;

                    if (!self.settings.full_light_path and !vertex.state.started_specular and !class.specular) {
                        continue;
                    }

                    var next_vertex = vertices.new();

                    next_vertex.* = vertex.*;
                    next_vertex.path_count = vertex.path_count * path_count;
                    next_vertex.split_weight = vertex.split_weight * sample_result.split_weight;

                    if (class.specular) {
                        next_vertex.state.treat_as_singular = true;

                        if (next_vertex.state.primary_ray) {
                            next_vertex.state.started_specular = true;
                        }
                    } else if (!class.straight) {
                        next_vertex.state.treat_as_singular = false;
                        next_vertex.state.primary_ray = false;
                    }

                    next_vertex.throughput_old = next_vertex.throughput;
                    next_vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

                    next_vertex.probe.ray.origin = isec.offsetP(sample_result.wi);
                    next_vertex.probe.ray.setDirection(sample_result.wi, ro.Ray_max_t);
                    next_vertex.probe.depth += 1;

                    if (!class.straight) {
                        next_vertex.state.from_subsurface = isec.subsurface();
                        next_vertex.origin = isec.p;
                    }

                    if (0.0 == next_vertex.probe.wavelength) {
                        next_vertex.probe.wavelength = sample_result.wavelength;
                    }

                    if (class.transmission) {
                        const ior = next_vertex.interfaceChangeIor(&isec, sample_result.wi, sampler, worker.scene);
                        const eta = ior.eta_i / ior.eta_t;
                        next_vertex.throughput *= @as(Vec4f, @splat(eta * eta));
                    }
                }

                sampler.incrementPadding();
            }
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
        material_split: bool,
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

        const camera_sample = camera.sampleTo(
            filter_crop,
            vertex.probe.time,
            isec.p,
            sampler,
            worker.scene,
        ) orelse return false;

        const wi = -camera_sample.dir;
        const p = isec.offsetP(wi);
        var tprobe = vertex.probe.clone(Ray.init(p, wi, 0.0, camera_sample.t));

        const tr = worker.visibility(&tprobe, isec, &vertex.interfaces, sampler) orelse return false;

        const bxdf_result = mat_sample.evaluate(wi, material_split);

        const wo = mat_sample.super().wo;
        const n = mat_sample.super().interpolatedNormal();
        var nsc = hlp.nonSymmetryCompensation(wi, wo, isec.geo_n, n);

        const material = isec.material(worker.scene);
        if (isec.subsurface() and material.denseSSSOptimization()) {
            const ior_t = vertex.interfaces.surroundingIor(worker.scene);
            const eta = material.ior() / ior_t;
            nsc *= eta * eta;
        }

        const weight: Vec4f = @splat(camera_sample.pdf * nsc * vertex.split_weight);
        const result = weight * (tr * vertex.throughput * bxdf_result.reflection);

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
