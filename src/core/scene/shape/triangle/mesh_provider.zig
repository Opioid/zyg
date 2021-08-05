const Mesh = @import("mesh.zig").Mesh;
const Shape = @import("../shape.zig").Shape;
const Resources = @import("../../../resource/manager.zig").Manager;
const triangle = @import("triangle.zig");
const bvh = @import("bvh/tree.zig");
const base = @import("base");
usingnamespace base;
usingnamespace base.math;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Part = struct {
    start_index: u32,
    num_indices: u32,
    material_index: u32,
};

const Handler = struct {
    pub const Parts = std.ArrayListUnmanaged(Part);
    pub const Triangles = std.ArrayListUnmanaged(triangle.Index_triangle);
    pub const Positions = std.ArrayListUnmanaged(Vec3f);

    parts: Parts = .{},
    triangles: Triangles = .{},
    positions: Positions = .{},

    pub fn deinit(self: *Handler, alloc: *Allocator) void {
        self.positions.deinit(alloc);
        self.triangles.deinit(alloc);
        self.parts.deinit(alloc);
    }
};

pub const Provider = struct {
    pub fn load(self: Provider, alloc: *Allocator, name: []const u8, resources: *Resources) !Shape {
        _ = self;

        var handler = Handler{};
        defer handler.deinit(alloc);

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
                    try loadGeometry(alloc, &handler, entry.value_ptr.*);
                }
            }
        }

        // for (handler.positions.items) |p| {
        //     std.debug.print("{}\n", .{p});
        // }

        var mesh = Mesh{
            .tree = .{
                .data = try bvh.Indexed_data.init(alloc, @intCast(u32, handler.triangles.items.len)),
            },
        };

        for (handler.triangles.items) |t, i| {
            mesh.tree.data.triangles[i] = .{
                .a = t.i[0],
                .b = t.i[1],
                .c = t.i[2],
                .bts = 0,
                .part = 0,
            };
        }

        const positions = handler.positions.items;
        mesh.tree.data.positions = try alloc.alloc(Vec4f, positions.len);

        for (positions) |p, i| {
            mesh.tree.data.positions[i] = Vec4f.init3(p.v[0], p.v[1], p.v[2]);
        }

        return Shape{ .Triangle_mesh = mesh };
    }

    fn loadGeometry(alloc: *Allocator, handler: *Handler, value: std.json.Value) !void {
        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "parts", entry.key_ptr.*)) {
                //loadGeometry(alloc, &handler, entry.value_ptr.*);

                const parts = entry.value_ptr.*.Array.items;

                handler.parts = try Handler.Parts.initCapacity(alloc, parts.len);

                for (parts) |p| {
                    const start_index = json.readUintMember(p, "start_index", 0);
                    const num_indices = json.readUintMember(p, "num_indices", 0);
                    const material_index = json.readUintMember(p, "material_index", 0);
                    try handler.parts.append(alloc, .{
                        .start_index = start_index,
                        .num_indices = num_indices,
                        .material_index = material_index,
                    });
                }
            } else if (std.mem.eql(u8, "vertices", entry.key_ptr.*)) {
                var viter = entry.value_ptr.Object.iterator();
                while (viter.next()) |ventry| {
                    if (std.mem.eql(u8, "positions", ventry.key_ptr.*)) {
                        const positions = ventry.value_ptr.*.Array.items;
                        const num_positions = positions.len / 3;

                        handler.positions = try Handler.Positions.initCapacity(alloc, num_positions);
                        try handler.positions.resize(alloc, num_positions);

                        for (handler.positions.items) |*p, i| {
                            p.* = Vec3f.init3(
                                json.readFloat(positions[i * 3 + 0]),
                                json.readFloat(positions[i * 3 + 1]),
                                json.readFloat(positions[i * 3 + 2]),
                            );
                        }
                    }
                }
            } else if (std.mem.eql(u8, "indices", entry.key_ptr.*)) {
                const indices = entry.value_ptr.*.Array.items;
                const num_triangles = indices.len / 3;

                handler.triangles = try Handler.Triangles.initCapacity(alloc, num_triangles);
                try handler.triangles.resize(alloc, num_triangles);

                for (handler.triangles.items) |*t, i| {
                    t.*.i[0] = @intCast(u32, indices[i * 3 + 0].Integer);
                    t.*.i[1] = @intCast(u32, indices[i * 3 + 1].Integer);
                    t.*.i[2] = @intCast(u32, indices[i * 3 + 2].Integer);
                }
            }
        }
    }
};
