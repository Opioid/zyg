const SamplerFactory = @import("../sampler/sampler.zig").Factory;
const SurfaceFactory = @import("../rendering/integrator/surface/integrator.zig").Factory;
const VolumeFactory = @import("../rendering/integrator/volume/integrator.zig").Factory;
const LighttracerFactory = @import("../rendering/integrator/particle/lighttracer.zig").Factory;
const cam = @import("../camera/perspective.zig");
const Pipeline = @import("../rendering/postprocessor/pipeline.zig").Pipeline;
const Sink = @import("../exporting/sink.zig").Sink;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Exporters = std.ArrayListUnmanaged(Sink);

pub const PhotonSettings = struct {
    num_photons: u32 = 0,
    max_bounces: u32 = 2,

    iteration_threshold: f32 = 0.0,
    search_radius: f32 = 0.01,
    merge_radius: f32 = 0.0025,
    coarse_search_radius: f32 = 0.1,

    full_light_path: bool = false,
};

pub const View = struct {
    samplers: SamplerFactory = undefined,

    surfaces: ?SurfaceFactory = null,
    volumes: ?VolumeFactory = null,
    lighttracers: ?LighttracerFactory = null,

    camera: cam.Perspective,

    pipeline: Pipeline,

    num_samples_per_pixel: u32 = 1,
    num_particles_per_pixel: u32 = 0,

    photon_settings: PhotonSettings = .{},

    pub fn deinit(self: *View, alloc: Allocator) void {
        self.pipeline.deinit(alloc);
        self.camera.deinit(alloc);
    }

    pub fn configure(self: *View, alloc: Allocator) !void {
        try self.pipeline.configure(alloc, self.camera);

        const spp = if (self.num_samples_per_pixel > 0) self.num_samples_per_pixel else self.num_particles_per_pixel;
        self.camera.sample_spacing = 1.0 / @sqrt(@intToFloat(f32, spp));
    }

    pub fn numParticleSamplesPerPixel(self: View) u32 {
        const lt = self.lighttracers orelse return 0;

        return self.num_particles_per_pixel * lt.settings.num_samples;
    }
};

pub const Take = struct {
    scene_filename: []u8,

    view: View,

    exporters: Exporters = .{},

    pub fn init() Take {
        return Take{
            .scene_filename = &.{},
            .view = .{
                .camera = cam.Perspective{},
                .pipeline = .{},
            },
        };
    }

    pub fn deinit(self: *Take, alloc: Allocator) void {
        for (self.exporters.items) |*e| {
            e.deinit(alloc);
        }

        self.exporters.deinit(alloc);
        self.view.deinit(alloc);
        alloc.free(self.scene_filename);
    }
};
