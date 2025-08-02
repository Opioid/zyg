const prj = @import("project.zig");
const Instance = prj.Instance;
const Prototype = prj.Prototype;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Exporter = struct {
    pub fn write(
        alloc: Allocator,
        name: []const u8,
        materials: []const u8,
        prototypes: []const Prototype,
        instances: []const Instance,
    ) !void {
        var out: std.io.Writer.Allocating = .init(alloc);
        var stream: std.json.Stringify = .{
            .writer = &out.writer,
            .options = .{ .whitespace = .indent_4 },
        };
        defer out.deinit();

        try stream.beginObject();

        if (materials.len > 0) {
            try stream.objectField("materials");

            try stream.beginWriteRaw();
            try stream.writer.writeAll(materials);
            stream.endWriteRaw();
        }

        try stream.objectField("prototypes");
        {
            try stream.beginArray();

            for (prototypes) |prototype| {
                try stream.beginObject();

                try stream.objectField("type");
                try stream.write("Prop");

                try stream.objectField("shape");
                try stream.beginObject();
                if (prototype.shape_file.len > 0) {
                    try stream.objectField("file");
                    try stream.write(prototype.shape_file);
                } else {
                    try stream.objectField("type");
                    try stream.write(prototype.shape_type);
                }
                try stream.endObject();

                try stream.objectField("materials");
                try stream.beginArray();
                for (prototype.materials) |material| {
                    try stream.write(material);
                }
                try stream.endArray();
                try stream.endObject();
            }

            try stream.endArray();
        }

        try stream.objectField("instances");
        {
            try stream.beginObject();

            try stream.objectField("prototypes");
            {
                try stream.beginArray();

                for (instances) |instance| {
                    try stream.write(instance.prototype);
                }

                try stream.endArray();
            }

            try stream.objectField("transformations");
            {
                try stream.beginArray();

                for (instances) |instance| {
                    try stream.write(@as([*]const f32, @ptrCast(&instance.transformation.r))[0..16]);
                }

                try stream.endArray();
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
