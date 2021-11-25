const SamplerFactory = @import("../sampler/sampler.zig").Factory;
const SurfaceFactory = @import("../rendering/integrator/surface/integrator.zig").Factory;
const VolumeFactory = @import("../rendering/integrator/volume/integrator.zig").Factory;
const LighttracerFactory = @import("../rendering/integrator/particle/lighttracer.zig").Factory;
const cam = @import("../camera/perspective.zig");
const Pipeline = @import("../rendering/postprocessor/pipeline.zig").Pipeline;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const View = struct {
    samplers: SamplerFactory = undefined,

    surfaces: ?SurfaceFactory = null,
    volumes: ?VolumeFactory = null,
    lighttracers: ?LighttracerFactory = null,

    camera: cam.Perspective,

    pipeline: Pipeline,

    num_samples_per_pixel: u32 = 1,
    num_particles_per_pixel: u32 = 0,

    pub fn deinit(self: *View, alloc: *Allocator) void {
        self.pipeline.deinit(alloc);
        self.camera.deinit(alloc);
    }

    pub fn configure(self: *View, alloc: *Allocator) !void {
        try self.pipeline.configure(alloc, self.camera);
    }

    pub fn numParticleSamplesPerPixel(self: View) u32 {
        const lt = self.lighttracers orelse return 0;

        return self.num_particles_per_pixel * lt.settings.num_samples;
    }
};

pub const Take = struct {
    scene_filename: []u8,

    view: View,

    pub fn init(alloc: *Allocator) !Take {
        return Take{
            .scene_filename = &.{},
            .view = .{
                .camera = try cam.Perspective.init(alloc),
                .pipeline = .{},
            },
        };
    }

    pub fn deinit(self: *Take, alloc: *Allocator) void {
        self.view.deinit(alloc);

        alloc.free(self.scene_filename);
    }
};
