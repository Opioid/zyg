pub const Texture = @import("texture.zig").Texture;
const Image = @import("../image.zig").Image;
const Resources = @import("../../resource/manager.zig").Manager;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    UnsupportedImageType,
};

pub const Provider = struct {
    pub fn loadFile(alloc: *Allocator, name: []const u8, resources: *Resources) !Texture {
        const image_id = try resources.loadFile(Image, alloc, name);

        const image = resources.get(Image, image_id) orelse unreachable;

        return switch (image.*) {
            .Byte3 => Texture{ .type = Texture.Type.Byte3_sRGB, .image = image_id },
            else => Error.UnsupportedImageType,
        };

        //   return Texture{ .image = image_id };
    }
};
