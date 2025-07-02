const Particles = @import("particle_generator.zig").Particles;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Exporter = struct {
    pub fn write(
        alloc: Allocator,
        name: []const u8,
        particles: *const Particles,
    ) !void {
        var out: std.ArrayListUnmanaged(u8) = .{};
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

                try stream.beginObject();
                try stream.objectField("material_index");
                try stream.write(0);
                try stream.objectField("start_index");
                try stream.write(0);
                try stream.objectField("num_indices");
                try stream.write(0);
                try stream.endObject();

                try stream.endArray();
            }

            try stream.objectField("primitive_topology");
            try stream.write("point_list");

            try stream.objectField("vertices");
            {
                try stream.beginObject();

                try stream.objectField("positions");
                {
                    try stream.beginArray();

                    for (particles.positions) |pos| {
                        try stream.write(pos.v[0]);
                        try stream.write(pos.v[1]);
                        try stream.write(pos.v[2]);
                    }

                    try stream.endArray();
                }

                try stream.objectField("velocities");
                {
                    try stream.beginArray();

                    for (particles.velocities) |vel| {
                        try stream.write(vel.v[0]);
                        try stream.write(vel.v[1]);
                        try stream.write(vel.v[2]);
                    }

                    try stream.endArray();
                }

                try stream.endObject();
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
};
