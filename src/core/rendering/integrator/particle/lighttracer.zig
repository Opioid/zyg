const Context = @import("../../../scene/context.zig").Context;
const vt = @import("../../../scene/vertex.zig");
const Vertex = vt.Vertex;
const VertexPool = vt.Pool;
const MaterialSample = @import("../../../scene/material/material_sample.zig").Sample;
const bxdf = @import("../../../scene/material/bxdf.zig");
const Worker = @import("../../worker.zig").Worker;
const Camera = @import("../../../camera/camera.zig").Camera;
const Sensor = @import("../../../rendering/sensor/sensor.zig").Sensor;
const Light = @import("../../../scene/light/light.zig").Light;
const MediumStack = @import("../../../scene/prop/medium.zig").Stack;
const SampleFrom = @import("../../../scene/shape/sample.zig").From;
const Fragment = @import("../../../scene/shape/intersection.zig").Fragment;
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
        max_depth: hlp.Depth,
        full_light_path: bool,
    };

    settings: Settings,

    const Self = @This();

    pub fn li(self: Self, frame: u32, worker: *Worker) void {
        const world_bounds = if (self.settings.full_light_path) worker.context.scene.aabb() else worker.context.scene.causticAabb();

        const sampler = worker.pickSampler(0);

        var light_id: u32 = undefined;
        var light_sample: SampleFrom = undefined;
        const vertex = generateLightVertex(
            frame,
            world_bounds,
            sampler,
            worker.context,
            &light_id,
            &light_sample,
        ) orelse return;

        const light = worker.context.scene.light(light_id);

        self.integrate(vertex, worker, light, light_sample);
    }

    fn integrate(self: Self, input: Vertex, worker: *Worker, light: Light, light_sample: SampleFrom) void {
        const camera = worker.context.camera;
        const sensor = worker.sensor;

        const max_depth = self.settings.max_depth;

        var vertices: VertexPool = undefined;
        vertices.start(input);

        while (vertices.iterate()) {
            while (vertices.consume()) |vertex| {
                const total_depth = vertex.probe.depth.total();

                if (vertex.probe.depth.surface >= max_depth.surface or vertex.probe.depth.volume >= max_depth.volume) {
                    continue;
                }

                const sampler = worker.pickSampler(total_depth);

                var frag: Fragment = undefined;
                worker.context.nextEvent(vertex, &frag, sampler);
                if (.Absorb == frag.event or .Abort == frag.event or !frag.hit()) {
                    break;
                }

                if (0 == vertex.probe.depth.surface) {
                    const pdf: Vec4f = @splat(light_sample.pdf());
                    const energy = light.evaluateFrom(frag.p, light_sample, sampler, worker.context) / pdf;
                    vertex.throughput *= energy;
                }

                const mat_sample = vertex.sample(&frag, sampler, true, worker.context);

                const max_splits = VertexPool.maxSplits(vertex, total_depth);

                if (mat_sample.canEvaluate() and (vertex.state.started_specular or self.settings.full_light_path)) {
                    _ = directCamera(camera, sensor, vertex, &frag, &mat_sample, max_splits, sampler, worker.context);

                    if (hlp.russianRoulette(&vertex.throughput, sampler.sample1D())) {
                        continue;
                    }
                }

                var bxdf_samples: bxdf.Samples = undefined;
                const sample_results = mat_sample.sample(sampler, max_splits, &bxdf_samples);
                const path_count: u32 = @intCast(sample_results.len);

                for (sample_results) |sample_result| {
                    const path = sample_result.path;

                    if (!self.settings.full_light_path and !vertex.state.started_specular and .Specular != path.scattering) {
                        continue;
                    }

                    var next_vertex = vertices.new();

                    next_vertex.* = vertex.*;
                    next_vertex.path_count = vertex.path_count * path_count;
                    next_vertex.split_weight = vertex.split_weight * sample_result.split_weight;

                    if (.Specular == path.scattering) {
                        next_vertex.state.specular = true;
                        next_vertex.state.singular = path.singular;

                        if (vertex.state.primary_ray) {
                            next_vertex.state.started_specular = true;
                        }
                    } else if (.Straight != path.event) {
                        next_vertex.state.specular = false;
                        next_vertex.state.singular = false;
                        next_vertex.state.primary_ray = false;
                    }

                    next_vertex.throughput *= sample_result.reflection / @as(Vec4f, @splat(sample_result.pdf));

                    next_vertex.probe.ray = frag.offsetRay(sample_result.wi, ro.RayMaxT);
                    next_vertex.probe.depth.increment(&frag);

                    if (.Straight != path.event) {
                        next_vertex.origin = frag.p;
                    }

                    if (0.0 == next_vertex.probe.wavelength) {
                        next_vertex.probe.wavelength = sample_result.wavelength;
                    }

                    if (.Transmission == path.event) {
                        const ior = next_vertex.interfaceChangeIor(sample_result.wi, &frag, &mat_sample, worker.context.scene);
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
        context: Context,
        light_id: *u32,
        light_sample: *SampleFrom,
    ) ?Vertex {
        const s2 = sampler.sample2D();
        const l = context.scene.randomLight(s2[0]);
        const time = context.absoluteTime(frame, s2[1]);

        const light = context.scene.light(l.offset);
        light_sample.* = light.sampleFrom(time, sampler, bounds, context.scene) orelse return null;
        light_sample.mulAssignPdf(l.pdf);

        light_id.* = l.offset;

        sampler.incrementPadding();

        return Vertex.init(Ray.init(light_sample.p, light_sample.dir, 0.0, ro.RayMaxT), time);
    }

    fn directCamera(
        camera: *const Camera,
        sensor: *Sensor,
        vertex: *const Vertex,
        frag: *const Fragment,
        mat_sample: *const MaterialSample,
        max_material_splits: u32,
        sampler: *Sampler,
        context: Context,
    ) void {
        if (!frag.visibleInCamera(context.scene)) {
            return;
        }

        const fr = sensor.filter_radius_int;

        var crop = camera.crop();

        var filter_crop = crop + Vec4i{ -fr, -fr, fr, fr };
        filter_crop[2] -= filter_crop[0] + 1;
        filter_crop[3] -= filter_crop[1] + 1;

        crop[2] -= crop[0] + 1;
        crop[3] -= crop[1] + 1;

        const wo = mat_sample.super().wo;
        const n = mat_sample.super().interpolatedNormal();

        for (0..camera.numLayers()) |l| {
            const layer: u32 = @truncate(l);

            const camera_sample = camera.sampleTo(
                layer,
                filter_crop,
                vertex.probe.time,
                frag.p,
                sampler,
                context.scene,
            ) orelse continue;

            const wi = -camera_sample.dir;
            const p = frag.offsetP(wi);
            const tprobe = vertex.probe.clone(Ray.init(p, wi, 0.0, camera_sample.t));

            var tr: Vec4f = @splat(1.0);
            if (!context.visibility(tprobe, sampler, &tr)) {
                continue;
            }

            const bxdf_result = mat_sample.evaluate(wi, max_material_splits);

            const nsc = hlp.nonSymmetryCompensation(wi, wo, frag.geo_n, n);

            const weight: Vec4f = @splat(camera_sample.pdf * nsc * vertex.split_weight);
            const result = weight * (tr * vertex.throughput * bxdf_result.reflection);

            sensor.splatSample(layer, camera_sample, result, crop);
        }
    }
};
