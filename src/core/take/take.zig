const cam = @import("../camera/perspective.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const View = struct {
    camera: cam.Perspective,
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
