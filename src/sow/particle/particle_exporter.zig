const Particles = @import("particle_generator.zig").Particles;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Exporter = struct {
    pub fn write(
        alloc: Allocator,
        name: []const u8,
        particles: *const Particles,
    ) !void {
        var out: std.io.Writer.Allocating = .init(alloc);
        var stream: std.json.Stringify = .{
            .writer = &out.writer,
            .options = .{ .whitespace = .indent_4 },
        };
        defer out.deinit();

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

            try stream.objectField("frames_per_second");
            try stream.write(particles.frames_per_second);

            try stream.objectField("point_radius");
            try stream.write(particles.radius);

            try stream.objectField("vertices");
            {
                try stream.beginObject();

                try stream.objectField("positions");
                {
                    try stream.beginArray();

                    for (particles.position_samples) |ps| {
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

                if (particles.radius_samples.len > 0) {
                    try stream.objectField("radius_samples");
                    {
                        try stream.beginArray();

                        for (particles.radius_samples) |rs| {
                            try stream.beginArray();

                            for (rs) |radius| {
                                try stream.write(radius);
                            }

                            try stream.endArray();
                        }

                        try stream.endArray();
                    }
                }

                try stream.endObject();
            }

            try stream.endObject();
        }

        try stream.endObject();

        var file = try std.fs.cwd().createFile(name, .{});
        defer file.close();

        var file_buffer: [4096]u8 = undefined;
        var txt_writer = file.writer(&file_buffer);

        _ = try txt_writer.interface.writeAll(out.getWritten());
        try txt_writer.end();
    }
};
