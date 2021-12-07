pub const Texture = @import("texture.zig").Texture;
const img = @import("../image.zig");
const Image = img.Image;
const Resources = @import("../../resource/manager.zig").Manager;
const Variants = @import("base").memory.VariantMap;
const math = @import("base").math;
const Vec2f = math.Vec2f;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    UnsupportedImageType,
};

pub const Usage = enum { Color, Emission, Normal, Roughness, Surface, Mask };

pub const Provider = struct {
    pub fn loadFile(
        alloc: *Allocator,
        name: []const u8,
        options: Variants,
        scale: Vec2f,
        resources: *Resources,
    ) !Texture {
        const usage = options.queryOrDef("usage", Usage.Color);

        var swizzle = options.query(img.Swizzle, "swizzle");
        if (null == swizzle) {
            swizzle = switch (usage) {
                .Color, .Emission => .XYZ,
                .Normal, .Surface => .XY,
                .Roughness => .X,
                .Mask => .W,
            };
        }

        var image_options = try options.cloneExcept(alloc, "usage");
        defer image_options.deinit(alloc);

        try image_options.set(alloc, "swizzle", swizzle.?);

        const image_id = try resources.loadFile(Image, alloc, name, image_options);
        const image = resources.get(Image, image_id) orelse unreachable;

        return switch (image.*) {
            .Byte1 => Texture{ .type = .Byte1_unorm, .image = image_id, .scale = scale },
            .Byte2 => Texture{
                .type = if (.Normal == usage) .Byte2_snorm else .Byte2_unorm,
                .image = image_id,
                .scale = scale,
            },
            .Byte3 => Texture{ .type = .Byte3_sRGB, .image = image_id, .scale = scale },
            .Half3 => Texture{ .type = .Half3, .image = image_id, .scale = scale },
            .Float1 => Texture{ .type = .Float1, .image = image_id, .scale = scale },
            .Float1Sparse => Texture{ .type = .Float1Sparse, .image = image_id, .scale = scale },
            .Float2 => Texture{ .type = .Float2, .image = image_id, .scale = scale },
            else => Error.UnsupportedImageType,
        };
    }
};
