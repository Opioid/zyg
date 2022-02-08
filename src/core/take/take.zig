const SamplerFactory = @import("../sampler/sampler.zig").Factory;
const SurfaceFactory = @import("../rendering/integrator/surface/integrator.zig").Factory;
const VolumeFactory = @import("../rendering/integrator/volume/integrator.zig").Factory;
const LighttracerFactory = @import("../rendering/integrator/particle/lighttracer.zig").Factory;
const cam = @import("../camera/perspective.zig");
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

    surfaces: SurfaceFactory = .{ .AOV = .{
        .settings = .{
            .value = .AO,
            .num_samples = 1,
            .max_bounces = 1,
            .radius = 1.0,
            .photons_not_only_through_specular = false,
        },
    } },

    volumes: VolumeFactory = .{ .Multi = .{} },

    lighttracers: LighttracerFactory = .{ .settings = .{
        .num_samples = 0,
        .min_bounces = 0,
        .max_bounces = 0,
        .full_light_path = false,
    } },

    camera: cam.Perspective,

    num_samples_per_pixel: u32 = 0,
    num_particles_per_pixel: u32 = 0,

    photon_settings: PhotonSettings = .{},

    pub fn deinit(self: *View, alloc: Allocator) void {
        self.camera.deinit(alloc);
    }

    pub fn configure(self: *View) void {
        const spp = if (self.num_samples_per_pixel > 0) self.num_samples_per_pixel else self.num_particles_per_pixel;
        self.camera.sample_spacing = 1.0 / @sqrt(@intToFloat(f32, spp));
    }

    pub fn numParticleSamplesPerPixel(self: View) u32 {
        return self.num_particles_per_pixel * self.lighttracers.settings.num_samples;
    }
};

pub const Take = struct {
    scene_filename: []u8 = &.{},

    view: View,

    exporters: Exporters = .{},

    pub fn init(alloc: Allocator) !Take {
        return Take{ .view = .{ .camera = try cam.Perspective.init(alloc) } };
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
