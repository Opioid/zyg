const file = @import("../file/file.zig");
const Image = @import("image.zig").Image;
const Swizzle = Image.Swizzle;
const ExrReader = @import("encoding/exr/exr_reader.zig").Reader;
const IesReader = @import("encoding/ies/ies_reader.zig").Reader;
const PngReader = @import("encoding/png/png_reader.zig").Reader;
const RgbeReader = @import("encoding/rgbe/rgbe_reader.zig").Reader;
const SubReader = @import("encoding/sub/sub_reader.zig").Reader;
const Resources = @import("../resource/manager.zig").Manager;
const Result = @import("../resource/result.zig").Result;

const Variants = @import("base").memory.VariantMap;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Provider = struct {
    const Error = error{
        UnknownImageType,
    };

    pub fn deinit(self: *Provider, alloc: Allocator) void {
        _ = self;
        _ = alloc;
    }

    pub fn loadFile(
        self: *Provider,
        alloc: Allocator,
        name: []const u8,
        options: Variants,
        resources: *Resources,
    ) !Result(Image) {
        _ = self;

        var stream = try resources.fs.readStream(alloc, name);
        defer stream.deinit();

        const file_type = try file.queryType(stream);

        const swizzle = options.queryOr("swizzle", Swizzle.XYZ);

        if (.EXR == file_type) {
            const color = options.queryOr("color", false);
            return .{ .data = try ExrReader.read(alloc, stream, swizzle, color) };
        }

        if (.IES == file_type) {
            return .{ .data = try IesReader.read(alloc, &stream) };
        }

        if (.PNG == file_type) {
            const invert = options.queryOr("invert", false);
            return .{ .data = try PngReader.read(alloc, stream, swizzle, invert, resources.threads) };
        }

        if (.RGBE == file_type) {
            return .{ .data = try RgbeReader.read(alloc, stream) };
        }

        if (.SUB == file_type) {
            return SubReader.read(alloc, stream);
        }

        return Error.UnknownImageType;
    }
};
