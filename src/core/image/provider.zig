const file = @import("../file/file.zig");
const img = @import("image.zig");
const Swizzle = img.Swizzle;
const Image = img.Image;
const ExrReader = @import("encoding/exr/reader.zig").Reader;
const IesReader = @import("encoding/ies/reader.zig").Reader;
const PngReader = @import("encoding/png/reader.zig").Reader;
const RgbeReader = @import("encoding/rgbe/reader.zig").Reader;
const SubReader = @import("encoding/sub/reader.zig").Reader;
const Resources = @import("../resource/manager.zig").Manager;
const Variants = @import("base").memory.VariantMap;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Provider = struct {
    const Error = error{
        UnknownImageType,
    };

    png_reader: PngReader = .{},

    previous_name: []u8,

    pub fn init(alloc: Allocator) !Provider {
        var buffer = try alloc.alloc(u8, 256);
        std.mem.set(u8, buffer, 0);

        return Provider{ .previous_name = buffer };
    }

    pub fn deinit(self: *Provider, alloc: Allocator) void {
        alloc.free(self.previous_name);
        self.png_reader.deinit(alloc);
    }

    pub fn loadFile(
        self: *Provider,
        alloc: Allocator,
        name: []const u8,
        options: Variants,
        resources: *Resources,
    ) !Image {
        var stream = try resources.fs.readStream(alloc, name);
        defer stream.deinit();

        const resolved_name = resources.fs.lastResolvedName();

        const same_file = std.mem.startsWith(u8, self.previous_name, resolved_name);

        if (self.previous_name.len < resolved_name.len) {
            self.previous_name = try alloc.realloc(self.previous_name, resolved_name.len);
        }

        std.mem.copy(u8, self.previous_name, resolved_name);

        const file_type = file.queryType(&stream);

        const swizzle = options.queryOrDef("swizzle", Swizzle.XYZ);

        if (.EXR == file_type) {
            const color = options.queryOrDef("color", false);

            return ExrReader.read(alloc, &stream, swizzle, color);
        }

        if (.IES == file_type) {
            return IesReader.read(alloc, &stream);
        }

        if (.PNG == file_type) {
            const invert = options.queryOrDef("invert", false);

            if (same_file) {
                return try self.png_reader.createFromBuffer(alloc, swizzle, invert);
            }

            return try self.png_reader.read(alloc, &stream, swizzle, invert);
        }

        if (.RGBE == file_type) {
            return RgbeReader.read(alloc, &stream);
        }

        if (.SUB == file_type) {
            return SubReader.read(alloc, &stream);
        }

        return Error.UnknownImageType;
    }
};
