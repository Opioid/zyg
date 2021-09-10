const file = @import("../file/file.zig");
const img = @import("image.zig");
const Swizzle = img.Swizzle;
const Image = img.Image;
const PngReader = @import("encoding/png/reader.zig").Reader;
const Resources = @import("../resource/manager.zig").Manager;
const Variants = @import("base").memory.VariantMap;

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

    pub fn loadFile(
        self: *Provider,
        alloc: *Allocator,
        name: []const u8,
        options: Variants,
        resources: *Resources,
    ) !Image {
        var stream = try resources.fs.readStream(name);
        defer stream.deinit();

        const file_type = file.queryType(&stream);

        if (file.Type.PNG == file_type) {
            const swizzle = options.query("swizzle", Swizzle.XYZ);
            return try self.png_reader.read(alloc, &stream, swizzle);
        }

        return Error.UnknownImageType;
    }
};
