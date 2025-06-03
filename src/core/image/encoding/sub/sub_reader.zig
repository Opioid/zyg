const img = @import("../../image.zig");
const Image = img.Image;
const ReadStream = @import("../../../file/read_stream.zig").ReadStream;
const Result = @import("../../../resource/result.zig").Result;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const json = base.json;
const Bitfield = base.memory.Bitfield;
const Variants = base.memory.VariantMap;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Reader = struct {
    const Error = error{
        NoImageDeclaration,
        NoImageDescription,
        InvalidDimensions,
        UndefinedImageType,
        NoPixels,
        EmptyTopology,
    };

    pub fn read(alloc: Allocator, stream: ReadStream) !Result(Image) {
        try stream.seekTo(4);

        var json_size: u64 = 0;
        _ = try stream.read(std.mem.asBytes(&json_size));

        var json_string = try alloc.alloc(u8, json_size);
        defer alloc.free(json_string);

        _ = try stream.read(json_string);

        var json_strlen = json_size;
        while (0 == json_string[json_strlen - 1]) {
            json_strlen -= 1;
        }

        var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json_string[0..json_strlen], .{});
        defer parsed.deinit();

        const root = parsed.value;

        const image_node = root.object.get("image") orelse return Error.NoImageDeclaration;

        const description_node = image_node.object.get("description") orelse return Error.NoImageDescription;

        const dimensions = json.readVec4i3Member(description_node, "dimensions", @splat(-1));

        if (-1 == dimensions[0]) {
            return Error.InvalidDimensions;
        }

        const offset = json.readVec4i3Member(description_node, "offset", @splat(0));

        const image_type = try readImageType(description_node);
        //   const topology_node =

        const pixels_node = image_node.object.get("pixels") orelse return Error.NoPixels;

        var pixels_offset: u64 = 0;
        var pixels_size: u64 = 0;

        {
            var iter = pixels_node.object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "binary", entry.key_ptr.*)) {
                    pixels_offset = json.readUInt64Member(entry.value_ptr.*, "offset", 0);
                    pixels_size = json.readUInt64Member(entry.value_ptr.*, "size", 0);
                }
            }
        }

        const binary_start = json_size + 4 + @sizeOf(u64);

        const description = img.Description.init3D(dimensions);

        if (image_node.object.get("topology")) |topology_node| {
            var topology_offset: u64 = 0;
            var topology_size: u64 = 0;

            {
                var iter = topology_node.object.iterator();
                while (iter.next()) |entry| {
                    if (std.mem.eql(u8, "binary", entry.key_ptr.*)) {
                        topology_offset = json.readUInt64Member(entry.value_ptr.*, "offset", 0);
                        topology_size = json.readUInt64Member(entry.value_ptr.*, "size", 0);
                        break;
                    }
                }
            }

            if (0 == topology_size) {
                return Error.EmptyTopology;
            }

            var meta = Variants{};
            try meta.set(alloc, "offset", offset);
            errdefer meta.deinit(alloc);

            const num_pixels = img.Description.numPixels(description.dimensions);

            var field = try Bitfield.init(alloc, num_pixels);
            defer field.deinit(alloc);

            try stream.seekTo(binary_start + topology_offset);
            _ = try stream.read(std.mem.sliceAsBytes(field.slice()));

            try stream.seekTo(binary_start + pixels_offset);

            if (.Byte1 == image_type) {
                var image = try img.Byte1.init(alloc, description);

                var i: u64 = 0;
                const len = num_pixels;
                while (i < len) : (i += 1) {
                    if (field.get(i)) {
                        var val: u8 = undefined;
                        _ = try stream.read(std.mem.asBytes(&val));
                        image.pixels[0][i] = val;
                    } else {
                        image.pixels[0][i] = 0;
                    }
                }

                return .{ .data = Image{ .Byte1 = image }, .meta = meta };
            }

            if (.Float1 == image_type) {
                var image = try img.Float1Sparse.init(alloc, description);

                var i: u64 = 0;
                const len = num_pixels;
                while (i < len) : (i += 1) {
                    if (field.get(i)) {
                        var val: f32 = undefined;
                        _ = try stream.read(std.mem.asBytes(&val));
                        try image.storeSequentially(alloc, @intCast(i), val);
                    }
                }

                return .{ .data = Image{ .Float1Sparse = image }, .meta = meta };

                // var image = try img.Float1.init(alloc, description);

                // var i: u64 = 0;
                // const len = num_pixels;
                // while (i < len) : (i += 1) {
                //     if (field.get(i)) {
                //         var val: f32 = undefined;
                //         _ = try stream.read(std.mem.asBytes(&val));
                //         image.pixels[i] = val;
                //     } else {
                //         image.pixels[i] = 0.0;
                //     }
                // }

                // return Image{ .Float1 = image };
            }

            if (.Float2 == image_type) {
                var image = try img.Float2.init(alloc, description);

                var i: u64 = 0;
                const len = num_pixels;
                while (i < len) : (i += 1) {
                    if (field.get(i)) {
                        var val: Vec2f = undefined;
                        _ = try stream.read(std.mem.asBytes(&val));
                        image.pixels[0][i] = val;
                    } else {
                        image.pixels[0][i] = @splat(0.0);
                    }
                }

                return .{ .data = Image{ .Float2 = image }, .meta = meta };
            }
        }

        return Error.NoPixels;
    }

    pub const ImageType = enum {
        Byte1,
        Float1,
        Float2,
    };

    fn readImageType(value: std.json.Value) !ImageType {
        const node = value.object.get("type") orelse return Error.UndefinedImageType;

        const type_name = node.string;

        if (std.mem.eql(u8, "Byte1", type_name)) {
            return ImageType.Byte1;
        }

        if (std.mem.eql(u8, "Float1", type_name)) {
            return ImageType.Float1;
        }

        if (std.mem.eql(u8, "Float2", type_name)) {
            return ImageType.Float2;
        }

        return Error.UndefinedImageType;
    }
};
