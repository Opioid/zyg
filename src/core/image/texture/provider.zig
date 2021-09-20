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

pub const Usage = enum { Color, Normal, Roughness, Mask };

pub const Provider = struct {
    pub fn loadFile(
        alloc: *Allocator,
        name: []const u8,
        options: Variants,
        resources: *Resources,
    ) !Texture {
        const usage = options.query("usage", Usage.Color);

        var swizzle: img.Swizzle = undefined;
        switch (usage) {
            .Color => {
                swizzle = .XYZ;
            },
            .Normal => {
                swizzle = .XY;
            },
            .Roughness => {
                swizzle = .X;
            },
            .Mask => {
                swizzle = .W;
            },
        }

        var image_options = Variants{};
        defer image_options.deinit(alloc);
        try image_options.set(alloc, "swizzle", swizzle);

        const image_id = try resources.loadFile(Image, alloc, name, image_options);

        const image = resources.get(Image, image_id) orelse unreachable;

        return switch (image.*) {
            .Byte1 => Texture{ .type = Texture.Type.Byte1_unorm, .image = image_id },
            .Byte2 => Texture{ .type = Texture.Type.Byte2_snorm, .image = image_id },
            .Byte3 => Texture{ .type = Texture.Type.Byte3_sRGB, .image = image_id },
            .Half3 => Texture{ .type = Texture.Type.Half3, .image = image_id },
            else => Error.UnsupportedImageType,
        };
    }
};
