const Context = @import("../scene/context.zig").Context;
const Camera = @import("../camera/camera.zig").Camera;
const Sensor = @import("../rendering/sensor/sensor.zig").Sensor;
const Scene = @import("../scene/scene.zig").Scene;
const vt = @import("../scene/vertex.zig");
const Vertex = vt.Vertex;
const RayDif = vt.RayDif;
const Renderstate = @import("../scene/renderstate.zig").Renderstate;
const Probe = @import("../scene/shape/probe.zig").Probe;
const Material = @import("../scene/material/material.zig").Material;
const MaterialSample = @import("../scene/material/material_sample.zig").Sample;
const hlp = @import("../scene/material/material_helper.zig");
const ro = @import("../scene/ray_offset.zig");
const int = @import("../scene/shape/intersection.zig");
const Fragment = int.Fragment;
const Volume = int.Volume;
const DifferentialSurface = int.DifferentialSurface;
const Texture = @import("../image/texture/texture.zig").Texture;
const ts = @import("../image/texture/texture_sampler.zig");
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

    pub fn render(
        self: *Self,
        frame: u32,
        tile: Vec4i,
        iteration: u32,
        num_samples: u32,
        num_expected_samples: u32,
    ) void {
        const camera = self.context.camera;
        const scene = self.context.scene;
        const layer = self.context.layer;
        const sensor = self.sensor;

        var rng = &self.rng;

        var crop = camera.super().crop;
        crop[2] -= crop[0] + 1;
        crop[3] -= crop[1] + 1;

        var isolated_bounds = sensor.isolatedTile(tile);
        isolated_bounds[2] -= isolated_bounds[0];
        isolated_bounds[3] -= isolated_bounds[1];

        const fr = sensor.filter_radius_int;
        const r = camera.super().resolution + @as(Vec2i, @splat(2 * fr));
        const a = @as(u32, @intCast(r[0])) * @as(u32, @intCast(r[1]));
        const o = @as(u64, iteration) * a;
        const so = iteration / num_expected_samples;

        const y_back = tile[3];
        var y: i32 = tile[1];
        while (y <= y_back) : (y += 1) {
            const pixel_n: u32 = @intCast((y + fr) * r[0]);

            const x_back = tile[2];
            var x: i32 = tile[0];
            while (x <= x_back) : (x += 1) {
                const pixel_id = pixel_n + @as(u32, @intCast(x + fr));

                rng.start(0, @as(u64, pixel_id) + o);

                const sample_index = @as(u64, pixel_id) * @as(u64, num_expected_samples) + @as(u64, iteration);
                const tsi: u32 = @truncate(sample_index);
                const seed = @as(u32, @truncate(sample_index >> 32)) + so;

                self.samplers[0].startPixel(tsi, seed);

                const pixel = Vec2i{ x, y };

                var s: u32 = 0;
                while (s < num_samples) : (s += 1) {
                    self.aov.clear();

                    const sample = sensor.cameraSample(pixel, &self.samplers[0]);
                    const vertex = camera.generateVertex(sample, layer, frame, scene);

                    const ivalue = self.surface_integrator.li(vertex, self);

                    sensor.addSample(layer, sample, ivalue, self.aov, crop, isolated_bounds);

                    self.samplers[0].incrementSample();
                }
            }
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
