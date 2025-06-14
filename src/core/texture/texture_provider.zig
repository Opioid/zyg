pub const Texture = @import("texture.zig").Texture;
const Image = @import("../image/image.zig").Image;
const Resources = @import("../resource/manager.zig").Manager;

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
    Weight,
};

pub const Provider = struct {
    pub fn loadFile(
        alloc: Allocator,
        name: []const u8,
        options: Variants,
        sampler: Texture.Mode,
        scale: Vec2f,
        resources: *Resources,
    ) !Texture {
        const usage = options.queryOr("usage", Usage.Color);

        const color = switch (usage) {
            .Color, .ColorAndOpacity, .Emission => true,
            else => false,
        };

        var swizzle = options.query(Image.Swizzle, "swizzle");
        if (null == swizzle) {
            swizzle = switch (usage) {
                .ColorAndOpacity => .XYZW,
                .Color, .Emission => .XYZ,
                .Normal => .XY,
                .Opacity => .W,
                .Weight => .X,
            };
        }

        var image_options = try options.cloneExcept(alloc, "usage");
        defer image_options.deinit(alloc);

        if (color) {
            try image_options.set(alloc, "color", true);
        }

        try image_options.set(alloc, "swizzle", swizzle.?);

        const image_id = try resources.loadFile(Image, alloc, name, image_options);

        return try createTexture(image_id, usage, sampler, scale, resources);
    }

    pub fn createTexture(image_id: u32, usage: Usage, sampler: Texture.Mode, scale: Vec2f, resources: *Resources) !Texture {
        const image = resources.get(Image, image_id) orelse return Error.InvalidImageId;

        return switch (image.*) {
            .Byte1 => Texture.initImage(.Byte1_unorm, image_id, sampler, scale),
            .Byte2 => Texture.initImage(if (.Normal == usage) .Byte2_snorm else .Byte2_unorm, image_id, sampler, scale),
            .Byte4 => Texture.initImage(.Byte4_sRGB, image_id, sampler, scale),
            .Byte3 => Texture.initImage(.Byte3_sRGB, image_id, sampler, scale),
            .Half1 => Texture.initImage(.Half1, image_id, sampler, scale),
            .Half3 => Texture.initImage(.Half3, image_id, sampler, scale),
            .Half4 => Texture.initImage(.Half4, image_id, sampler, scale),
            .Float1 => Texture.initImage(.Float1, image_id, sampler, scale),
            .Float1Sparse => Texture.initImage(.Float1Sparse, image_id, sampler, scale),
            .Float2 => Texture.initImage(.Float2, image_id, sampler, scale),
            .Float3 => Texture.initImage(.Float3, image_id, sampler, scale),
            .Float4 => Texture.initImage(.Float4, image_id, sampler, scale),
        };
    }
};
