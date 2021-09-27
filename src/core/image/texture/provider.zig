pub const Texture = @import("texture.zig").Texture;
const img = @import("../image.zig");
const Image = img.Image;
const Resources = @import("../../resource/manager.zig").Manager;
const Variants = @import("base").memory.VariantMap;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    UnsupportedImageType,
};

pub const Usage = enum { Color, Normal, Roughness, Surface, Mask };

pub const Provider = struct {
    pub fn loadFile(
        alloc: *Allocator,
        name: []const u8,
        options: Variants,
        resources: *Resources,
    ) !Texture {
        const usage = options.query("usage", Usage.Color);

        const swizzle: img.Swizzle = switch (usage) {
            .Color => .XYZ,
            .Normal, .Surface => .XY,
            .Roughness => .X,
            .Mask => .W,
        };

        var image_options = Variants{};
        defer image_options.deinit(alloc);
        try image_options.set(alloc, "swizzle", swizzle);

        const image_id = try resources.loadFile(Image, alloc, name, image_options);

        const image = resources.get(Image, image_id) orelse unreachable;

        return switch (image.*) {
            .Byte1 => Texture{ .type = .Byte1_unorm, .image = image_id },
            .Byte2 => Texture{ .type = if (.Normal == usage) .Byte2_snorm else .Byte2_unorm, .image = image_id },
            .Byte3 => Texture{ .type = .Byte3_sRGB, .image = image_id },
            .Half3 => Texture{ .type = .Half3, .image = image_id },
            else => Error.UnsupportedImageType,
        };
    }
};
