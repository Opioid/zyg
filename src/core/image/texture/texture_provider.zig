pub const Texture = @import("texture.zig").Texture;
const img = @import("../image.zig");
const Image = img.Image;
const Resources = @import("../../resource/manager.zig").Manager;

const base = @import("base");
const Variants = base.memory.VariantMap;
const math = base.math;
const Vec2f = math.Vec2f;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    InvalidImageId,
};

pub const Usage = enum {
    Color,
    ColorAndOpacity,
    Emission,
    Normal,
    Opacity,
    Roughness,
    Surface,
};

pub const Provider = struct {
    pub fn loadFile(
        alloc: Allocator,
        name: []const u8,
        options: Variants,
        scale: Vec2f,
        resources: *Resources,
    ) !Texture {
        const usage = options.queryOrDef("usage", Usage.Color);

        const color = switch (usage) {
            .Color, .ColorAndOpacity, .Emission => true,
            else => false,
        };

        var swizzle = options.query(img.Swizzle, "swizzle");
        if (null == swizzle) {
            swizzle = switch (usage) {
                .ColorAndOpacity => .XYZW,
                .Color, .Emission => .XYZ,
                .Normal, .Surface => .XY,
                .Opacity => .W,
                .Roughness => .X,
            };
        }

        var image_options = try options.cloneExcept(alloc, "usage");
        defer image_options.deinit(alloc);

        if (color) {
            try image_options.set(alloc, "color", true);
        }

        try image_options.set(alloc, "swizzle", swizzle.?);

        const image_id = try resources.loadFile(Image, alloc, name, image_options);

        return try createTexture(image_id, usage, scale, resources);
    }

    pub fn createTexture(image_id: u32, usage: Usage, scale: Vec2f, resources: *Resources) !Texture {
        const image = resources.get(Image, image_id) orelse return Error.InvalidImageId;

        return switch (image.*) {
            .Byte1 => Texture{ .type = .Byte1_unorm, .image = image_id, .scale = scale },
            .Byte2 => Texture{
                .type = if (.Normal == usage) .Byte2_snorm else .Byte2_unorm,
                .image = image_id,
                .scale = scale,
            },
            .Byte3 => Texture{ .type = .Byte3_sRGB, .image = image_id, .scale = scale },
            .Half1 => Texture{ .type = .Half1, .image = image_id, .scale = scale },
            .Half3 => Texture{ .type = .Half3, .image = image_id, .scale = scale },
            .Half4 => Texture{ .type = .Half4, .image = image_id, .scale = scale },
            .Float1 => Texture{ .type = .Float1, .image = image_id, .scale = scale },
            .Float1Sparse => Texture{ .type = .Float1Sparse, .image = image_id, .scale = scale },
            .Float2 => Texture{ .type = .Float2, .image = image_id, .scale = scale },
            .Float3 => Texture{ .type = .Float3, .image = image_id, .scale = scale },
            .Float4 => Texture{ .type = .Float4, .image = image_id, .scale = scale },
        };
    }
};
