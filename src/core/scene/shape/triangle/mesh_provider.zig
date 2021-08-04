const Mesh = @import("mesh.zig").Mesh;
const Shape = @import("../shape.zig").Shape;
const Resources = @import("../../../resource/manager.zig").Manager;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Part = struct {
    start_index: u32,
    num_indices: u32,
    material_index: u32,
};

const Handler = struct {
    parts: std.ArrayListUnmanaged(Part) = .{},

    pub fn deinit(self: *Handler, alloc: *Allocator) void {
        self.parts.deinit(alloc);
    }
};

pub const Provider = struct {
    pub fn load(self: Provider, alloc: *Allocator, name: []const u8, resources: *Resources) !Shape {
        _ = self;

        handler = Handler{};

        {
            var stream = try resources.fs.readStream(name);
            defer stream.deinit();

            const buffer = try stream.reader.unbuffered_reader.readAllAlloc(alloc, std.math.maxInt(u64));
            defer alloc.free(buffer);

            var parser = std.json.Parser.init(alloc, false);
            defer parser.deinit();

            var document = try parser.parse(buffer);
            defer document.deinit();

            const root = document.root;

            var iter = root.Object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "geometry", entry.key_ptr.*)) {
                    loadGeometry(alloc, &handler, entry.value_ptr.*);
                }
            }
        }

        return Shape{ .Mesh = .{} };
    }

    fn loadGeometry(alloc: *Allocator, handler: *Handler, value: std.json.Value) !void {
        _ = alloc;
        _ = handler;
        _ = value;
    }
};
