const math = @import("base").math;
const Mat4x4 = math.Mat4x4;

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

pub const Prototype = struct {
    shape_file: []u8,
    materials: [][]u8,

    pub fn deinit(self: *Prototype, alloc: Allocator) void {
        for (self.materials) |m| {
            alloc.free(m);
        }

        alloc.free(self.materials);
        alloc.free(self.shape_file);
    }
};

pub const Instance = struct {
    prototype: u32,
    transformation: Mat4x4,
};

pub const Exporter = struct {
    pub fn write(
        alloc: Allocator,
        name: []const u8,
        prototypes: []const Prototype,
        instances: []const Instance,
    ) !void {
        var out: std.ArrayListUnmanaged(u8) = .{};
        defer out.deinit(alloc);

        var stream = std.json.writeStream(out.writer(alloc), .{ .whitespace = .indent_4 });
        defer stream.deinit();

        try stream.beginObject();

        try stream.objectField("prototypes");
        {
            try stream.beginArray();

            for (prototypes) |prototype| {
                try stream.beginObject();

                try stream.objectField("type");
                try stream.write("Prop");

                try stream.objectField("shape");
                try stream.beginObject();
                try stream.objectField("file");
                try stream.write(prototype.shape_file);
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

        var buffered = std.io.bufferedWriter(file.writer());
        var txt_writer = buffered.writer();

        _ = try txt_writer.write(out.items);

        try buffered.flush();
    }
};
