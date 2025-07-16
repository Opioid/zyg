const Model = @import("model.zig").Model;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub fn write(alloc: Allocator, name: []const u8, model: *const Model) !void {
    var out: List(u8) = .{};
    defer out.deinit(alloc);

    var stream = std.json.writeStream(out.writer(alloc), .{ .whitespace = .indent_4 });
    defer stream.deinit();

    try stream.beginObject();

    try stream.objectField("geometry");
    {
        try stream.beginObject();

        try stream.objectField("parts");
        {
            try stream.beginArray();

            for (model.parts) |part| {
                try stream.beginObject();
                try stream.objectField("material_index");
                try stream.write(part.material_index);
                try stream.objectField("start_index");
                try stream.write(part.start_index);
                try stream.objectField("num_indices");
                try stream.write(part.num_indices);
                try stream.endObject();
            }

            try stream.endArray();
        }

        try stream.objectField("primitive_topology");
        try stream.write("triangle_list");

        try stream.objectField("frames_per_second");
        try stream.write(30);

        try stream.objectField("vertices");
        {
            try stream.beginObject();

            try stream.objectField("positions");
            {
                try stream.beginArray();

                for (model.positions.items) |ps| {
                    try stream.beginArray();

                    for (ps) |pos| {
                        try stream.write(pos.v[0]);
                        try stream.write(pos.v[1]);
                        try stream.write(pos.v[2]);
                    }

                    try stream.endArray();
                }

                try stream.endArray();
            }

            try stream.objectField("normals");
            {
                try stream.beginArray();

                for (model.normals.items) |ns| {
                    try stream.beginArray();

                    for (ns) |norm| {
                        try stream.write(norm.v[0]);
                        try stream.write(norm.v[1]);
                        try stream.write(norm.v[2]);
                    }

                    try stream.endArray();
                }

                try stream.endArray();
            }

            try stream.objectField("texture_coordinates_0");
            {
                try stream.beginArray();

                for (model.uvs) |uv| {
                    try stream.write(uv[0]);
                    try stream.write(uv[1]);
                }

                try stream.endArray();
            }

            try stream.endObject();
        }

        try stream.objectField("indices");
        {
            try stream.beginArray();

            for (model.indices) |index| {
                try stream.write(index);
            }

            try stream.endArray();
        }

        try stream.endObject();
    }

    try stream.endObject();

    var file = try std.fs.cwd().createFile(name, .{});
    defer file.close();

    var buffered = std.io.bufferedWriter(file.writer());
    var txt_writer = buffered.writer();

    _ = try txt_writer.write(out.items);

    try buffered.flush();
}
