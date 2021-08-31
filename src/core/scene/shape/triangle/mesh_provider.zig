const Mesh = @import("mesh.zig").Mesh;
const Shape = @import("../shape.zig").Shape;
const Resources = @import("../../../resource/manager.zig").Manager;
const vs = @import("vertex_stream.zig");
const IndexTriangle = @import("triangle.zig").IndexTriangle;
const bvh = @import("bvh/tree.zig");
const Builder = @import("bvh/builder_sah.zig").BuilderSAH;
const file = @import("../../../file/file.zig");
const ReadStream = @import("../../../file/read_stream.zig").ReadStream;
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
    pub const Triangles = std.ArrayListUnmanaged(IndexTriangle);
    pub const Vec3fs = std.ArrayListUnmanaged(Vec3f);
    pub const u8s = std.ArrayListUnmanaged(u8);

    parts: Parts = .{},
    triangles: Triangles = .{},
    positions: Vec3fs = .{},
    normals: Vec3fs = .{},
    tangents: Vec3fs = .{},
    bitangent_signs: u8s = .{},

    pub fn deinit(self: *Handler, alloc: *Allocator) void {
        self.bitangent_signs.deinit(alloc);
        self.tangents.deinit(alloc);
        self.normals.deinit(alloc);
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

            if (file.Type.SUB == file.queryType(&stream)) {
                return loadBinary(alloc, &stream, resources.threads) catch |e| {
                    std.debug.print("Loading mesh \"{s}\": {}\n", .{ name, e });
                    return e;
                };
            }

            const buffer = try stream.reader.unbuffered_reader.readAllAlloc(alloc, std.math.maxInt(u64));
            defer alloc.free(buffer);

            var parser = std.json.Parser.init(alloc, false);
            defer parser.deinit();

            var document = parser.parse(buffer) catch |e| {
                std.debug.print("Loading mesh \"{s}\": {}\n", .{ name, e });
                return e;
            };
            defer document.deinit();

            const root = document.root;

            var iter = root.Object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "geometry", entry.key_ptr.*)) {
                    try loadGeometry(alloc, &handler, entry.value_ptr.*);
                }
            }
        }

        for (handler.parts.items) |p, i| {
            const triangles_start = p.start_index / 3;
            const triangles_end = (p.start_index + p.num_indices) / 3;

            for (handler.triangles.items[triangles_start..triangles_end]) |*t| {
                t.*.part = @intCast(u32, i);
            }
        }

        const vertices = vs.VertexStream{ .Json = .{
            .positions = handler.positions.items,
            .normals = handler.normals.items,
            .tangents = handler.tangents.items,
            .bitangent_signs = handler.bitangent_signs.items,
        } };

        var mesh = Mesh{};

        try buildBVH(alloc, &mesh, handler.triangles.items, vertices);

        return Shape{ .Triangle_mesh = mesh };
    }

    fn loadGeometry(alloc: *Allocator, handler: *Handler, value: std.json.Value) !void {
        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "parts", entry.key_ptr.*)) {
                const parts = entry.value_ptr.*.Array.items;

                handler.parts = try Handler.Parts.initCapacity(alloc, parts.len);

                for (parts) |p| {
                    const start_index = json.readUIntMember(p, "start_index", 0);
                    const num_indices = json.readUIntMember(p, "num_indices", 0);
                    const material_index = json.readUIntMember(p, "material_index", 0);
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

                        handler.positions = try Handler.Vec3fs.initCapacity(alloc, num_positions);
                        try handler.positions.resize(alloc, num_positions);

                        for (handler.positions.items) |*p, i| {
                            p.* = Vec3f.init3(
                                json.readFloat(positions[i * 3 + 0]),
                                json.readFloat(positions[i * 3 + 1]),
                                json.readFloat(positions[i * 3 + 2]),
                            );
                        }
                    } else if (std.mem.eql(u8, "normals", ventry.key_ptr.*)) {
                        const normals = ventry.value_ptr.*.Array.items;
                        const num_normals = normals.len / 3;

                        handler.normals = try Handler.Vec3fs.initCapacity(alloc, num_normals);
                        try handler.normals.resize(alloc, num_normals);

                        for (handler.normals.items) |*n, i| {
                            n.* = Vec3f.init3(
                                json.readFloat(normals[i * 3 + 0]),
                                json.readFloat(normals[i * 3 + 1]),
                                json.readFloat(normals[i * 3 + 2]),
                            );
                        }
                    } else if (std.mem.eql(u8, "tangents_and_bitangent_signs", ventry.key_ptr.*)) {
                        const tangents = ventry.value_ptr.*.Array.items;
                        const num_tangents = tangents.len / 4;

                        handler.tangents = try Handler.Vec3fs.initCapacity(alloc, num_tangents);
                        try handler.tangents.resize(alloc, num_tangents);

                        handler.bitangent_signs = try Handler.u8s.initCapacity(alloc, num_tangents);
                        try handler.bitangent_signs.resize(alloc, num_tangents);

                        for (handler.tangents.items) |*t, i| {
                            t.* = Vec3f.init3(json.readFloat(tangents[i * 4 + 0]), json.readFloat(tangents[i * 4 + 1]), json.readFloat(tangents[i * 4 + 2]));

                            handler.bitangent_signs.items[i] = if (json.readFloat(tangents[i * 4 + 3]) > 0.0) 0 else 1;
                        }
                    } else if (std.mem.eql(u8, "tangent_space", ventry.key_ptr.*)) {
                        const tangent_spaces = ventry.value_ptr.*.Array.items;
                        const num_tangent_spaces = tangent_spaces.len / 4;

                        handler.normals = try Handler.Vec3fs.initCapacity(alloc, num_tangent_spaces);
                        try handler.normals.resize(alloc, num_tangent_spaces);

                        handler.tangents = try Handler.Vec3fs.initCapacity(alloc, num_tangent_spaces);
                        try handler.tangents.resize(alloc, num_tangent_spaces);

                        handler.bitangent_signs = try Handler.u8s.initCapacity(alloc, num_tangent_spaces);
                        try handler.bitangent_signs.resize(alloc, num_tangent_spaces);

                        for (handler.normals.items) |*n, i| {
                            var ts = Quaternion.init4(
                                json.readFloat(tangent_spaces[i * 4 + 0]),
                                json.readFloat(tangent_spaces[i * 4 + 1]),
                                json.readFloat(tangent_spaces[i * 4 + 2]),
                                json.readFloat(tangent_spaces[i * 4 + 3]),
                            );

                            var bts: bool = false;

                            if (ts.v[3] < 0.0) {
                                ts.v[3] = -ts.v[3];
                                bts = true;
                            }

                            const tbn = quaternion.initMat3x3(ts);

                            n.* = Vec3f.init3(tbn.r[2].v[0], tbn.r[2].v[1], tbn.r[2].v[1]);

                            var t = &handler.tangents.items[i];
                            t.* = Vec3f.init3(tbn.r[0].v[0], tbn.r[0].v[1], tbn.r[0].v[1]);

                            handler.bitangent_signs.items[i] = if (bts) 1 else 0;
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

    const Error = error{
        NoGeometryNode,
        BitangentSignNotUInt8,
    };

    fn loadBinary(alloc: *Allocator, stream: *ReadStream, threads: *thread.Pool) !Shape {
        _ = threads;

        try stream.seekTo(4);

        var parts: []Part = &.{};
        defer alloc.free(parts);

        var vertices_offset: u64 = 0;
        var vertices_size: u64 = 0;

        var indices_offset: u64 = 0;
        var indices_size: u64 = 0;
        var index_bytes: u64 = 0;

        var num_vertices: u32 = 0;
        var num_indices: u32 = 0;

        var interleaved_vertex_stream: bool = false;
        var tangent_space_as_quaternion: bool = false;
        var has_uvs: bool = false;
        var has_tangents: bool = false;
        var delta_indices: bool = false;

        var json_size: u64 = 0;
        _ = try stream.read(std.mem.asBytes(&json_size));

        {
            var json_string = try alloc.alloc(u8, json_size);
            defer alloc.free(json_string);

            _ = try stream.read(json_string);

            var parser = std.json.Parser.init(alloc, false);
            defer parser.deinit();

            var document = try parser.parse(json_string);
            defer document.deinit();

            const geometry_node = document.root.Object.get("geometry") orelse {
                return Error.NoGeometryNode;
            };

            var iter = geometry_node.Object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "parts", entry.key_ptr.*)) {
                    const parts_slice = entry.value_ptr.Array.items;

                    parts = try alloc.alloc(Part, parts_slice.len);

                    for (parts_slice) |p, i| {
                        parts[i].start_index = json.readUIntMember(p, "start_index", 0);
                        parts[i].num_indices = json.readUIntMember(p, "num_indices", 0);
                        parts[i].material_index = json.readUIntMember(p, "material_index", 0);
                    }
                } else if (std.mem.eql(u8, "vertices", entry.key_ptr.*)) {
                    var viter = entry.value_ptr.Object.iterator();
                    while (viter.next()) |vn| {
                        if (std.mem.eql(u8, "binary", vn.key_ptr.*)) {
                            vertices_offset = json.readUInt64Member(vn.value_ptr.*, "offset", 0);
                            vertices_size = json.readUInt64Member(vn.value_ptr.*, "size", 0);
                        } else if (std.mem.eql(u8, "num_vertices", vn.key_ptr.*)) {
                            num_vertices = json.readUInt(vn.value_ptr.*);
                        } else if (std.mem.eql(u8, "layout", vn.key_ptr.*)) {
                            for (vn.value_ptr.Array.items) |ln| {
                                const semantic_name = json.readStringMember(ln, "semantic_name", "");
                                if (std.mem.eql(u8, "Tangent", semantic_name)) {
                                    has_tangents = true;
                                } else if (std.mem.eql(u8, "Tangent_space", semantic_name)) {
                                    tangent_space_as_quaternion = true;
                                } else if (std.mem.eql(u8, "Texture_coordinate", semantic_name)) {
                                    has_uvs = true;
                                } else if (std.mem.eql(u8, "Bitangent_sign", semantic_name)) {
                                    if (!std.mem.eql(u8, "UInt8", json.readStringMember(ln, "encoding", ""))) {
                                        return Error.BitangentSignNotUInt8;
                                    }

                                    if (0 == json.readUIntMember(ln, "stream", 0)) {
                                        interleaved_vertex_stream = true;
                                    }
                                }
                            }
                        }
                    }
                } else if (std.mem.eql(u8, "indices", entry.key_ptr.*)) {
                    var iiter = entry.value_ptr.Object.iterator();
                    while (iiter.next()) |in| {
                        if (std.mem.eql(u8, "binary", in.key_ptr.*)) {
                            indices_offset = json.readUInt64Member(in.value_ptr.*, "offset", 0);
                            indices_size = json.readUInt64Member(in.value_ptr.*, "size", 0);
                        } else if (std.mem.eql(u8, "num_indices", in.key_ptr.*)) {
                            num_indices = json.readUInt(in.value_ptr.*);
                        } else if (std.mem.eql(u8, "encoding", in.key_ptr.*)) {
                            const enc = json.readString(in.value_ptr.*);

                            if (std.mem.eql(u8, "Int16", enc)) {
                                index_bytes = 2;
                                delta_indices = true;
                            } else if (std.mem.eql(u8, "UInt16", enc)) {
                                index_bytes = 2;
                                delta_indices = false;
                            } else if (std.mem.eql(u8, "Int32", enc)) {
                                index_bytes = 4;
                                delta_indices = true;
                            } else {
                                index_bytes = 4;
                                delta_indices = false;
                            }
                        }
                    }
                }
            }
        }

        const binary_start = json_size + 4 + @sizeOf(u64);

        try stream.seekTo(binary_start + vertices_offset);

        var vertices: vs.VertexStream = undefined;
        defer vertices.deinit(alloc);

        if (interleaved_vertex_stream) {
            std.debug.print("interleaved\n", .{});
        } else {
            std.debug.print("not interleaved {}\n", .{num_vertices});

            var positions = try alloc.alloc(Vec3f, num_vertices);

            _ = try stream.read(std.mem.sliceAsBytes(positions));

            if (tangent_space_as_quaternion) {} else {
                var normals = try alloc.alloc(Vec3f, num_vertices);

                _ = try stream.read(std.mem.sliceAsBytes(normals));

                vertices = vs.VertexStream{ .Compact = try vs.Compact.init(positions, normals) };
            }
        }

        try stream.seekTo(binary_start + indices_offset);

        var indices = try alloc.alloc(u8, indices_size);
        defer alloc.free(indices);
        _ = try stream.read(indices);

        const num_triangles = num_indices / 3;
        var triangles = try alloc.alloc(IndexTriangle, num_triangles);
        defer alloc.free(triangles);

        if (4 == index_bytes) {
            if (delta_indices) {
                fillTrianglesDelta(i32, parts, indices, triangles);
            } else {
                fillTriangles(u32, parts, indices, triangles);
            }
        } else {
            if (delta_indices) {
                fillTrianglesDelta(i16, parts, indices, triangles);
            } else {
                fillTriangles(u16, parts, indices, triangles);
            }
        }

        var mesh = Mesh{};

        try buildBVH(alloc, &mesh, triangles, vertices);

        return Shape{ .Triangle_mesh = mesh };
    }

    fn buildBVH(alloc: *Allocator, mesh: *Mesh, triangles: []const IndexTriangle, vertices: vs.VertexStream) !void {
        var builder = try Builder.init(alloc, 16, 64, 4);
        defer builder.deinit(alloc);

        try builder.build(alloc, &mesh.tree, triangles, vertices);
    }

    fn fillTriangles(
        comptime I: type,
        parts: []const Part,
        index_buffer: []const u8,
        triangles: []IndexTriangle,
    ) void {
        const indices = std.mem.bytesAsSlice(I, index_buffer);

        for (parts) |p, i| {
            const triangles_start = p.start_index / 3;
            const triangles_end = (p.start_index + p.num_indices) / 3;

            for (triangles[triangles_start..triangles_end]) |*t, j| {
                const jj = triangles_start + j;

                t.*.i[0] = @intCast(u32, indices[jj * 3 + 0]);
                t.*.i[1] = @intCast(u32, indices[jj * 3 + 1]);
                t.*.i[2] = @intCast(u32, indices[jj * 3 + 2]);

                t.*.part = @intCast(u32, i);
            }
        }
    }

    fn fillTrianglesDelta(
        comptime I: type,
        parts: []const Part,
        index_buffer: []const u8,
        triangles: []IndexTriangle,
    ) void {
        const indices = std.mem.bytesAsSlice(I, index_buffer);

        var previous_index: i32 = 0;

        for (parts) |p, i| {
            const triangles_start = p.start_index / 3;
            const triangles_end = (p.start_index + p.num_indices) / 3;

            for (triangles[triangles_start..triangles_end]) |*t, j| {
                const jj = triangles_start + j;

                const a = previous_index + @intCast(i32, indices[jj * 3 + 0]);
                t.*.i[0] = @intCast(u32, a);

                const b = a + @intCast(i32, indices[jj * 3 + 1]);
                t.*.i[1] = @intCast(u32, b);

                const c = b + @intCast(i32, indices[jj * 3 + 2]);
                t.*.i[2] = @intCast(u32, c);

                t.*.part = @intCast(u32, i);

                previous_index = c;
            }
        }
    }
};
