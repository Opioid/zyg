const file = @import("../file/file.zig");
const Image = @import("image.zig").Image;
const PngReader = @import("encoding/png/reader.zig").Reader;
const Resources = @import("../resource/manager.zig").Manager;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Provider = struct {
    const Error = error{
        UnknownImageType,
    };

    png_reader: PngReader = .{},

    pub fn deinit(self: *Provider, alloc: *Allocator) void {
        self.png_reader.deinit(alloc);
    }

    pub fn loadFile(self: *Provider, alloc: *Allocator, name: []const u8, resources: *Resources) !Image {
        _ = self;
        _ = alloc;

        std.debug.print("{s}\n", .{name});

        var stream = try resources.fs.readStream(name);
        defer stream.deinit();

        const file_type = file.queryType(&stream);

        if (file.Type.PNG == file_type) {
            return try self.png_reader.read(alloc, &stream);
        }

        return Error.UnknownImageType;
    }
};
