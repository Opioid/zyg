const Sampler_factory = @import("../sampler/sampler.zig").Factory;
const Surface_factory = @import("../rendering/integrator/surface/integrator.zig").Factory;

const cam = @import("../camera/perspective.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const View = struct {
    samplers: Sampler_factory = undefined,

    surfaces: Surface_factory = undefined,

    camera: cam.Perspective,

    num_samples_per_pixel: u32 = 1,
};

pub const Take = struct {
    scene_filename: ?[]u8,

    view: View,

    pub fn init() Take {
        return .{
            .scene_filename = null,
            .view = .{ .camera = cam.Perspective{} },
        };
    }

    pub fn deinit(self: *Take, alloc: *Allocator) void {
        self.view.camera.deinit(alloc);

        if (self.scene_filename) |filename| alloc.free(filename);
    }
};
