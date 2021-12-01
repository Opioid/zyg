const img = @import("../../image.zig");
const Image = img.Image;
const ReadStream = @import("../../../file/read_stream.zig").ReadStream;

const base = @import("base");
const math = base.math;
const Vec3i = math.Vec3i;
const json = base.json;
const Bitfield = base.memory.Bitfield;

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

    pub fn read(alloc: *Allocator, stream: *ReadStream) !Image {
        try stream.seekTo(4);

        var json_size: u64 = 0;
        _ = try stream.read(std.mem.asBytes(&json_size));

        var json_string = try alloc.alloc(u8, json_size);
        defer alloc.free(json_string);

        _ = try stream.read(json_string);

        var parser = std.json.Parser.init(alloc, false);
        defer parser.deinit();

        var document = try parser.parse(json_string);
        defer document.deinit();

        const image_node = document.root.Object.get("image") orelse return Error.NoImageDeclaration;

        const description_node = image_node.Object.get("description") orelse return Error.NoImageDescription;

        const dimensions = json.readVec3iMember(description_node, "dimensions", Vec3i.init1(-1));

        if (-1 == dimensions.v[0]) {
            return Error.InvalidDimensions;
        }

        const offset = json.readVec3iMember(description_node, "offset", Vec3i.init1(0));
        _ = offset;

        const image_type = try readImageType(description_node);
        //   const topology_node =

        const pixels_node = image_node.Object.get("pixels") orelse return Error.NoPixels;

        var pixels_offset: u64 = 0;
        var pixels_size: u64 = 0;

        {
            var iter = pixels_node.Object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "binary", entry.key_ptr.*)) {
                    pixels_offset = json.readUInt64Member(entry.value_ptr.*, "offset", 0);
                    pixels_size = json.readUInt64Member(entry.value_ptr.*, "size", 0);
                }
            }
        }

        const binary_start = json_size + 4 + @sizeOf(u64);
        _ = binary_start;

        const description = img.Description.init3D(dimensions);

        if (image_node.Object.get("topology")) |topology_node| {
            var topology_offset: u64 = 0;
            var topology_size: u64 = 0;

            {
                var iter = topology_node.Object.iterator();
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

            var field = try Bitfield.init(alloc, description.numPixels());
            defer field.deinit(alloc);

            try stream.seekTo(binary_start + topology_offset);
            _ = try stream.read(std.mem.sliceAsBytes(field.slice()));

            try stream.seekTo(binary_start + pixels_offset);

            if (.Byte1 == image_type) {
                var image = try img.Byte1.init(alloc, description);

                return Image{ .Byte1 = image };
            }

            if (.Float1 == image_type) {
                var image = try img.Float1.init(alloc, description);

                var i: u64 = 0;
                const len = description.numPixels();
                while (i < len) : (i += 1) {
                    if (field.get(i)) {
                        var val: f32 = undefined;
                        _ = try stream.read(std.mem.asBytes(&val));
                        image.pixels[i] = val;
                    } else {
                        image.pixels[i] = 0.0;
                    }
                }

                return Image{ .Float1 = image };
            }

            if (.Float2 == image_type) {
                var image = try img.Float2.init(alloc, description);

                return Image{ .Float2 = image };
            }
        }

        return Error.NoPixels;
    }

    fn readImageType(value: std.json.Value) !img.Type {
        const node = value.Object.get("type") orelse return Error.UndefinedImageType;

        const type_name = node.String;

        if (std.mem.eql(u8, "Byte1", type_name)) {
            return img.Type.Byte1;
        }

        if (std.mem.eql(u8, "Float1", type_name)) {
            return img.Type.Float1;
        }

        if (std.mem.eql(u8, "Float2", type_name)) {
            return img.Type.Float2;
        }

        return Error.UndefinedImageType;
    }
};
