const Context = @import("../scene/context.zig").Context;
const Camera = @import("../camera/camera.zig").Camera;
const Sensor = @import("../rendering/sensor/sensor.zig").Sensor;
const Scene = @import("../scene/scene.zig").Scene;
const vt = @import("../scene/vertex.zig");
const Vertex = vt.Vertex;
const RayDif = vt.RayDif;
const Renderstate = @import("../scene/renderstate.zig").Renderstate;
const Probe = @import("../scene/shape/probe.zig").Probe;
const TileStackN = @import("tile_queue.zig").TileStackN;
const Material = @import("../scene/material/material.zig").Material;
const MaterialSample = @import("../scene/material/material_sample.zig").Sample;
const hlp = @import("../scene/material/material_helper.zig");
const ro = @import("../scene/ray_offset.zig");
const int = @import("../scene/shape/intersection.zig");
const Fragment = int.Fragment;
const Volume = int.Volume;
const DifferentialSurface = int.DifferentialSurface;
const Texture = @import("../texture/texture.zig").Texture;
const ts = @import("../texture/texture_sampler.zig");
const smpl = @import("../sampler/sampler.zig");
const Sampler = smpl.Sampler;
const surface = @import("integrator/surface/integrator.zig");
const VolumeIntegrator = @import("integrator/volume/volume_integrator.zig").Integrator;
const lt = @import("integrator/particle/lighttracer.zig");
const PhotonSettings = @import("../take/take.zig").PhotonSettings;
const PhotonMapper = @import("integrator/particle/photon/photon_mapper.zig").Mapper;
const PhotonMap = @import("integrator/particle/photon/photon_map.zig").Map;
const aov = @import("sensor/aov/aov_value.zig");

const base = @import("base");
const math = base.math;
const Mat3x3 = math.Mat3x3;
const Vec2b = math.Vec2b;
const Vec2i = math.Vec2i;
const Vec2ul = math.Vec2ul;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Ray = math.Ray;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Worker = struct {
    pub const TileDimensions = 16;
    const TileArea = TileDimensions * TileDimensions;

    const TileStack = TileStackN(TileArea);

    const Step = 16;

    context: Context = undefined,

    sensor: *Sensor = undefined,

    surface_integrator: *surface.Integrator = undefined,
    lighttracer: *lt.Lighttracer = undefined,

    rng: RNG = undefined,

    samplers: [2]Sampler = undefined,

    aov: aov.Value = undefined,

    photon_mapper: PhotonMapper = .{},
    photon_map: ?*PhotonMap = null,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.photon_mapper.deinit(alloc);
    }

    pub fn configure(
        self: *Self,
        alloc: Allocator,
        sensor: *Sensor,
        scene: *Scene,
        surface_integrator: *surface.Integrator,
        lighttracer: *lt.Lighttracer,
        samplers: smpl.Factory,
        aovs: aov.Factory,
        photon_settings: PhotonSettings,
        photon_map: ?*PhotonMap,
    ) !void {
        self.sensor = sensor;
        self.context.scene = scene;

        self.surface_integrator = surface_integrator;
        self.lighttracer = lighttracer;

        const rng = &self.rng;

        self.samplers[0] = samplers.create(rng);
        self.samplers[1] = .{ .Random = .{ .rng = rng } };

        self.aov = aovs.create();

        const max_bounces = if (photon_settings.num_photons > 0) photon_settings.max_bounces else 0;
        try self.photon_mapper.configure(alloc, .{
            .max_bounces = max_bounces,
            .full_light_path = photon_settings.full_light_path,
        }, rng);

        self.photon_map = photon_map;
    }

    fn curve(value: Vec4f) Vec4f {
        const p = Vec4f{
            std.math.pow(f32, value[0], 1.0 / 2.2),
            std.math.pow(f32, value[1], 1.0 / 2.2),
            std.math.pow(f32, value[2], 1.0 / 2.2),
            0.0,
        };

        return p;
    }

    // Running variance calculation as described in
    // https://www.johndcook.com/blog/standard_deviation/

    pub fn render(
        self: *Self,
        frame: u32,
        target_tile: Vec4i,
        iteration: u32,
        num_samples: u32,
        num_expected_samples: u32,
        qm_threshold: f32,
    ) void {
        const camera = self.context.camera;
        const scene = self.context.scene;
        const layer = self.context.layer;
        const sensor = self.sensor;
        const r = camera.super().resolution;
        const so = iteration / num_expected_samples;
        const offset = Vec2i{ target_tile[0], target_tile[1] };

        // Those values are only used for variance estimation
        // Exposure and tonemapping is not done here
        const ef: Vec4f = @splat(sensor.tonemapper.exposure_factor);
        const wp: f32 = 0.98;
        const qm_threshold_squared = qm_threshold * qm_threshold;

        var rng = &self.rng;

        var old_mm = [_]Vec4f{@splat(0)} ** TileArea;
        var old_ss = [_]Vec4f{@splat(0)} ** TileArea;

        var tile_stacks: [2]TileStack = undefined;

        var stack_a = &tile_stacks[0];
        var stack_b = &tile_stacks[1];

        stack_a.clear();
        stack_a.push(target_tile, offset);

        var s_start: u32 = 0;
        while (s_start < num_samples) {
            const s_end = @min(s_start + Step, num_samples);

            stack_b.clear();

            while (stack_a.pop(offset)) |tile| {
                const y_back = tile[3];
                var y = tile[1];
                var yy = @rem(y, TileDimensions);

                var tile_qm: f32 = 0.0;

                while (y <= y_back) : (y += 1) {
                    const x_back = tile[2];
                    var x = tile[0];
                    var xx = @rem(x, TileDimensions);
                    const pixel_n: u32 = @intCast(y * r[0]);

                    while (x <= x_back) : (x += 1) {
                        const ii: u32 = @intCast(yy * TileDimensions + xx);
                        xx += 1;

                        const pixel_id = pixel_n + @as(u32, @intCast(x));

                        const sample_index = @as(u64, pixel_id) * @as(u64, num_expected_samples) + @as(u64, iteration + s_start);
                        const tsi: u32 = @truncate(sample_index);
                        const seed = @as(u32, @truncate(sample_index >> 32)) + so;

                        rng.start(0, sample_index);
                        self.samplers[0].startPixel(tsi, seed);

                        const pixel = Vec2i{ x, y };

                        var old_m = old_mm[ii];
                        var old_s = old_ss[ii];

                        for (s_start..s_end) |cs| {
                            self.aov.clear();

                            const sample = sensor.cameraSample(pixel, &self.samplers[0]);
                            const vertex = camera.generateVertex(sample, layer, frame, scene);

                            const ivalue = self.surface_integrator.li(vertex, self);

                            // The weightd value is what was added to the pixel
                            const weighted = sensor.addSample(layer, sample, ivalue, self.aov);

                            // This clipped value is what we use for the noise estimate
                            const value = math.min4(@abs(ef * weighted), @splat(wp));

                            const new_m = old_m + (value - old_m) / @as(Vec4f, @splat(@floatFromInt(cs + 1)));

                            old_s += (value - old_m) * (value - new_m);
                            old_m = new_m;

                            self.samplers[0].incrementSample();
                        }

                        old_mm[ii] = old_m;
                        old_ss[ii] = old_s;

                        const variance = old_s / @as(Vec4f, @splat(@floatFromInt(s_end - 1)));

                        const std_dev = @sqrt(variance);

                        const mapped_value = curve(old_m);
                        const mapped_lower = curve(math.max4(old_m - std_dev, @splat(0.0)));
                        const mapped_upper = curve(old_m + std_dev);

                        const qm = math.max(math.hmax3(mapped_value - mapped_lower), math.hmax3(mapped_upper - mapped_value));

                        tile_qm = math.max(tile_qm, qm);
                    }

                    yy += 1;
                }

                const target_samples: u32 = @intFromFloat(@ceil(tile_qm / qm_threshold_squared));

                if (target_samples > s_end) {
                    if (s_end == 64) {
                        stack_b.pushQuartet(tile, offset, TileDimensions / 2 - 1);
                    } else if (s_end == 128) {
                        stack_b.pushQuartet(tile, offset, TileDimensions / 4 - 1);
                    } else if (s_end == 256) {
                        stack_b.pushQuartet(tile, offset, TileDimensions / 8 - 1);
                    } else if (s_end == 512) {
                        stack_b.pushQuartet(tile, offset, TileDimensions / 16 - 1);
                    } else {
                        stack_b.push(tile, offset);
                    }
                }
            }

            if (stack_b.empty()) {
                break;
            }

            s_start += Step;

            std.mem.swap(TileStack, stack_a, stack_b);
        }
    }

    pub fn particles(self: *Self, frame: u32, offset: u64, range: Vec2ul) void {
        var rng = &self.rng;
        rng.start(0, offset);

        const tsi: u32 = @truncate(range[0]);
        const seed: u32 = @truncate(range[0] >> 32);
        self.samplers[0].startPixel(tsi, seed);

        for (range[0]..range[1]) |_| {
            self.lighttracer.li(frame, self);

            self.samplers[0].incrementSample();
        }
    }

    pub fn bakePhotons(self: *Self, begin: u32, end: u32, frame: u32, iteration: u32) u32 {
        if (self.photon_map) |pm| {
            return self.photon_mapper.bake(pm, begin, end, frame, iteration, self.context);
        }

        return 0;
    }

    pub fn photonLi(self: *const Self, frag: *const Fragment, sample: *const MaterialSample, sampler: *Sampler) Vec4f {
        if (self.photon_map) |pm| {
            return pm.li(frag, sample, sampler, self.context);
        }

        return @splat(0.0);
    }

    pub inline fn pickSampler(self: *Self, bounce: u32) *Sampler {
        if (bounce < 3) {
            return &self.samplers[0];
        }

        return &self.samplers[1];
    }

    pub fn commonAOV(self: *Self, vertex: *const Vertex, frag: *const Fragment, mat_sample: *const MaterialSample) void {
        const primary_ray = vertex.state.primary_ray;

        if (primary_ray and self.aov.activeClass(.Albedo) and mat_sample.canEvaluate()) {
            self.aov.insert3(.Albedo, vertex.throughput * mat_sample.aovAlbedo());
        }

        if (vertex.probe.depth.surface > 0) {
            return;
        }

        if (self.aov.activeClass(.GeometricNormal)) {
            self.aov.insert3(.GeometricNormal, mat_sample.super().geometricNormal());
        }

        if (self.aov.activeClass(.ShadingNormal)) {
            self.aov.insert3(.ShadingNormal, mat_sample.super().shadingNormal());
        }

        if (self.aov.activeClass(.Roughness)) {
            self.aov.insert1(.Roughness, @sqrt(mat_sample.super().averageAlpha()));
        }

        if (self.aov.activeClass(.Depth)) {
            self.aov.insert1(.Depth, vertex.probe.ray.max_t);
        }

        if (self.aov.activeClass(.MaterialId)) {
            self.aov.insert1(
                .MaterialId,
                @floatFromInt(1 + self.context.scene.propMaterialId(frag.prop, frag.part)),
            );
        }
    }
};
