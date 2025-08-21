const Model = @import("model.zig").Model;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayList;

const VertexLayoutDescription = struct {
    pub const Encoding = enum {
        UInt8,
        UInt16,
        UInt32,
        Float32,
        Float32x2,
        Float32x3,
        Float32x4,

        pub fn string(self: Encoding) []const u8 {
            return switch (self) {
                .UInt8 => "UInt8",
                .UInt16 => "UInt16",
                .UInt32 => "UInt32",
                .Float32 => "Float32",
                .Float32x2 => "Float32x2",
                .Float32x3 => "Float32x3",
                .Float32x4 => "Float32x4",
            };
        }
    };

    pub const Element = struct {
        num_frames: u32 = 1,

        semantic_name: []const u8 = undefined,

        semantic_index: u32 = 0,

        encoding: Encoding = undefined,

        stream: u32 = 0,
        byte_offset: u32 = 0,

        pub fn write(self: Element, writer: anytype) !void {
            try writer.beginObject();
            try writer.objectField("num_frames");
            try writer.write(self.num_frames);

            try writer.objectField("semantic_name");
            try writer.write(self.semantic_name);

            try writer.objectField("semantic_index");
            try writer.write(self.semantic_index);

            try writer.objectField("encoding");
            try writer.write(self.encoding.string());

            try writer.objectField("stream");
            try writer.write(self.stream);

            try writer.objectField("byte_offset");
            try writer.write(self.byte_offset);

            try writer.endObject();
        }
    };
};

pub fn write(alloc: Allocator, name: []const u8, model: *const Model) !void {
    var file = try std.fs.cwd().createFile(name, .{});
    defer file.close();

    var buffered = std.io.bufferedWriter(file.writer());
    var stream = buffered.writer();

    try stream.writeAll("SUB\x00");

    var max_index: i64 = 0;
    var max_index_delta: i64 = 0;
    var min_index_delta: i64 = 0;

    {
        var previous_index: i64 = 0;

        for (model.indices) |i| {
            const si: i64 = @intCast(i);

            max_index = @max(max_index, si);

            const delta_index = si - previous_index;

            max_index_delta = @max(delta_index, max_index_delta);
            min_index_delta = @min(delta_index, min_index_delta);

            previous_index = si;
        }
    }

    var delta_indices = false;
    var index_bytes: u32 = 4;

    if (max_index <= 0x000000000000FFFF) {
        index_bytes = 2;
    }

    if (max_index_delta <= 0x0000000000007FFF and @abs(min_index_delta) <= 0x0000000000007FFF) {
        index_bytes = 2;
        delta_indices = true;
    } else if (max_index_delta <= 0x000000007FFFFFFF and @abs(min_index_delta) <= 0x000000007FFFFFFF) {
        delta_indices = true;
    }

    {
        var out: List(u8) = .{};
        defer out.deinit(alloc);

        var writer = std.json.writeStream(out.writer(alloc), .{ .whitespace = .minified });
        defer writer.deinit();

        try writer.beginObject();
        try writer.objectField("geometry");
        {
            try writer.beginObject();
            try writer.objectField("parts");
            {
                try writer.beginArray();

                for (model.parts) |part| {
                    try writer.beginObject();

                    try writer.objectField("start_index");
                    try writer.write(part.start_index);
                    try writer.objectField("num_indices");
                    try writer.write(part.num_indices);
                    try writer.objectField("material_index");
                    try writer.write(part.material_index);

                    try writer.endObject();
                }

                try writer.endArray();
            }

            try writer.objectField("primitive_topology");
            try writer.write("triangle_list");

            try writer.objectField("frame_duration");
            try writer.write(model.frame_duration);

            const num_vertices = model.positions.items[0].len;

            var vertices_binary_size: u64 = 0;

            // positions
            vertices_binary_size += model.positions.items.len * num_vertices * 12;
            // normals
            vertices_binary_size += model.normals.items.len * num_vertices * 12;
            // UVs
            vertices_binary_size += num_vertices * 8;

            // Vertices
            try writer.objectField("vertices");
            {
                try writer.beginObject();

                try binaryTag(&writer, 0, vertices_binary_size);

                try writer.objectField("num_vertices");
                try writer.write(model.positions.items[0].len);

                try writer.objectField("layout");
                try writer.beginArray();

                var element = VertexLayoutDescription.Element{};

                element.num_frames = @intCast(model.positions.items.len);
                element.semantic_name = "Position";
                element.encoding = .Float32x3;
                element.stream = 0;
                try element.write(&writer);

                element.num_frames = @intCast(model.normals.items.len);
                element.semantic_name = "Normal";
                element.encoding = .Float32x3;
                element.stream = 1;
                try element.write(&writer);

                element.num_frames = 1;
                element.semantic_name = "TextureCoordinate";
                element.encoding = .Float32x2;
                element.stream = 2;
                try element.write(&writer);

                try writer.endArray();

                try writer.endObject();
            }

            // Indices

            try writer.objectField("indices");
            {
                try writer.beginObject();

                try binaryTag(&writer, vertices_binary_size, model.indices.len * index_bytes);

                try writer.objectField("num_indices");
                try writer.write(model.indices.len);

                try writer.objectField("encoding");

                if (4 == index_bytes) {
                    if (delta_indices) {
                        try writer.write("Int32");
                    } else {
                        try writer.write("UInt32");
                    }
                } else {
                    if (delta_indices) {
                        try writer.write("Int16");
                    } else {
                        try writer.write("UInt16");
                    }
                }

                try writer.endObject();
            }

            try writer.endObject();
        }

        try writer.endObject();

        const json_size = out.items.len;
        const aligned_json_size: u64 = @intCast(json_size + json_size % 4);

        try stream.writeAll(std.mem.asBytes(&aligned_json_size));

        try stream.writeAll(out.items);

        for (0..aligned_json_size - json_size) |_| {
            try stream.writeByte(0);
        }
    }

    for (model.positions.items) |frame| {
        try stream.writeAll(std.mem.sliceAsBytes(frame));
    }

    for (model.normals.items) |frame| {
        try stream.writeAll(std.mem.sliceAsBytes(frame));
    }

    try stream.writeAll(std.mem.sliceAsBytes(model.uvs));

    if (4 == index_bytes) {
        var previous_index: i32 = 0;

        if (delta_indices) {
            for (model.indices) |i| {
                const a: i32 = @intCast(i);

                const delta_index: i32 = a - previous_index;
                try stream.writeAll(std.mem.asBytes(&delta_index));

                previous_index = a;
            }
        } else {
            try stream.writeAll(std.mem.sliceAsBytes(model.indices));
        }
    } else {
        if (delta_indices) {
            var previous_index: i32 = 0;

            for (model.indices) |i| {
                const a: i32 = @intCast(i);

                const delta_index: i16 = @intCast(a - previous_index);
                try stream.writeAll(std.mem.asBytes(&delta_index));

                previous_index = a;
            }
        } else {
            for (model.indices) |i| {
                const a: i16 = @intCast(i);

                try stream.writeAll(std.mem.asBytes(&a));
            }
        }
    }

    try buffered.flush();
}

fn binaryTag(writer: anytype, offset: u64, size: u64) !void {
    try writer.objectField("binary");
    try writer.beginObject();

    try writer.objectField("offset");
    try writer.write(offset);

    try writer.objectField("size");
    try writer.write(size);

    try writer.endObject();
}
