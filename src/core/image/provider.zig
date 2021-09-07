const Image = @import("image.zig").Image;
const Resources = @import("../resource/manager.zig").Manager;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Provider = struct {
    const Error = error{
        UnknownImage,
    };

    pub fn loadFile(self: Provider, alloc: *Allocator, name: []const u8, resources: *Resources) !Image {
        _ = self;
        _ = alloc;
        _ = resources;

        std.debug.print("{s}", .{name});

        return Error.UnknownImage;
    }
};
