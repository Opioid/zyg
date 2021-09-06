const Sampler_factory = @import("../sampler/sampler.zig").Factory;
const Surface_factory = @import("../rendering/integrator/surface/integrator.zig").Factory;
const cam = @import("../camera/perspective.zig");
const Pipeline = @import("../rendering/postprocessor/pipeline.zig").Pipeline;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const View = struct {
    samplers: Sampler_factory = undefined,

    surfaces: Surface_factory = Surface_factory{ .Invalid = .{} },

    camera: cam.Perspective,

    pipeline: Pipeline,

    num_samples_per_pixel: u32 = 1,

    pub fn deinit(self: *View, alloc: *Allocator) void {
        self.pipeline.deinit(alloc);
        self.camera.deinit(alloc);
    }

    pub fn configure(self: *View, alloc: *Allocator) !void {
        try self.pipeline.configure(alloc, self.camera);
    }
};

pub const Take = struct {
    scene_filename: []u8,

    view: View,

    pub fn init() Take {
        return .{
            .scene_filename = &.{},
            .view = .{ .camera = cam.Perspective{}, .pipeline = .{} },
        };
    }

    pub fn deinit(self: *Take, alloc: *Allocator) void {
        self.view.deinit(alloc);

        alloc.free(self.scene_filename);
    }
};
