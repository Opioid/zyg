const log = @import("../../log.zig");
const Shape = @import("shape.zig").Shape;
const TriangleMesh = @import("triangle/triangle_mesh.zig").Mesh;
const CurveMesh = @import("curve/curve_mesh.zig").Mesh;
const tvb = @import("triangle/vertex_buffer.zig");
const IndexTriangle = @import("triangle/triangle.zig").IndexTriangle;
const TriangleTree = @import("triangle/triangle_tree.zig").Tree;
const TriangleBuilder = @import("triangle/triangle_tree_builder.zig").Builder;
const CurveBuilder = @import("curve/curve_tree_builder.zig").Builder;
const HairReader = @import("curve/hair_reader.zig").Reader;
const Resources = @import("../../resource/manager.zig").Manager;
const Result = @import("../../resource/result.zig").Result;
const file = @import("../../file/file.zig");
const ReadStream = @import("../../file/read_stream.zig").ReadStream;

const base = @import("base");
const json = base.json;
const math = base.math;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;
const Pack4f = math.Pack4f;
const quaternion = math.quaternion;
const Quaternion = math.Quaternion;
const Threads = base.thread.Pool;
const ThreadContext = Threads.Context;
const Variants = base.memory.VariantMap;
const RNG = base.rnd.Generator;

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
    pub const Vec3fs = std.ArrayListUnmanaged(Pack3f);
    pub const Vec2fs = std.ArrayListUnmanaged(Vec2f);
    pub const u8s = std.ArrayListUnmanaged(u8);

    parts: Parts = .empty,
    triangles: Triangles = .empty,
    positions: Vec3fs = .empty,
    normals: Vec3fs = .empty,
    tangents: Vec3fs = .empty,
    uvs: Vec2fs = .empty,
    bitangent_signs: u8s = .empty,

    pub fn deinit(self: *Handler, alloc: Allocator) void {
        self.bitangent_signs.deinit(alloc);
        self.uvs.deinit(alloc);
        self.tangents.deinit(alloc);
        self.normals.deinit(alloc);
        self.positions.deinit(alloc);
        self.triangles.deinit(alloc);
        self.parts.deinit(alloc);
    }
};

const Error = error{
    NoVertices,
    NoGeometryNode,
    BitangentSignNotUInt8,
    PartIndicesOutOfBounds,
};

pub const Provider = struct {
    pub const Descriptor = struct {
        num_parts: u32,
        num_primitives: u32,
        num_vertices: u32,
        positions_stride: u32,
        normals_stride: u32,
        tangents_stride: u32,
        uvs_stride: u32,

        parts: ?[*]const u32,
        indices: ?[*]const u32,
        positions: [*]const f32,
        normals: [*]const f32,
        tangents: ?[*]const f32,
        uvs: ?[*]const f32,
    };

    num_indices: u32 = undefined,
    index_bytes: u64 = undefined,
    delta_indices: bool = undefined,
    handler: Handler = undefined,
    tree: TriangleTree = .{},
    parts: []Part = undefined,
    indices: []u8 = undefined,
    vertices: tvb.Buffer = undefined,
    desc: Descriptor = undefined,
    alloc: Allocator = undefined,
    threads: *Threads = undefined,

    pub fn deinit(self: *Provider, alloc: Allocator) void {
        _ = self;
        _ = alloc;
    }

    pub fn commitAsync(self: *Provider, resources: *Resources) void {
        if (0 == self.tree.nodes.len) {
            return;
        }

        if (resources.shapes.getLast()) |last| {
            switch (last.*) {
                .TriangleMesh => |*m| {
                    std.mem.swap(TriangleTree, &m.tree, &self.tree);
                    m.calculateAreas();
                },
                else => {},
            }
        }
    }

    pub fn loadFile(self: *Provider, alloc: Allocator, name: []const u8, options: Variants, resources: *Resources) !Result(Shape) {
        _ = options;

        var handler = Handler{};

        {
            var stream = try resources.fs.readStream(alloc, name);
            defer stream.deinit();

            if (file.Type.HAIR == file.queryType(stream)) {
                var curves = try HairReader.read(alloc, stream);
                defer {
                    alloc.free(curves.curves);
                    curves.vertices.deinit(alloc);
                }

                var mesh = CurveMesh{};

                var builder = try CurveBuilder.init(alloc, 16, 64, 4);
                defer builder.deinit(alloc);

                try builder.build(alloc, &mesh.tree, curves.curves, curves.vertices, resources.threads);

                return .{ .data = .{ .CurveMesh = mesh } };
            } else if (file.Type.SUB == file.queryType(stream)) {
                const mesh = self.loadBinary(alloc, stream, resources) catch |e| {
                    log.err("Loading mesh \"{s}\": {}", .{ name, e });
                    return e;
                };

                return .{ .data = .{ .TriangleMesh = mesh } };
            }

            const buffer = try stream.readAll(alloc);
            defer alloc.free(buffer);

            var parsed = std.json.parseFromSlice(std.json.Value, alloc, buffer, .{}) catch |e| {
                log.err("Loading mesh \"{s}\": {}", .{ name, e });
                return e;
            };
            defer parsed.deinit();

            const root = parsed.value;

            var iter = root.object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "geometry", entry.key_ptr.*)) {
                    try loadGeometry(alloc, &handler, entry.value_ptr.*);
                }
            }
        }

        if (0 == handler.positions.items.len) {
            return Error.NoVertices;
        }

        for (handler.parts.items, 0..) |p, i| {
            const triangles_start = p.start_index / 3;
            const triangles_end = (p.start_index + p.num_indices) / 3;

            for (handler.triangles.items[triangles_start..triangles_end]) |*t| {
                t.part = @intCast(i);
            }
        }

        var mesh = try TriangleMesh.init(alloc, @intCast(handler.parts.items.len));

        for (handler.parts.items, 0..) |p, i| {
            mesh.setMaterialForPart(i, p.material_index);
        }

        resources.commitAsync();

        self.handler = handler;
        self.alloc = alloc;
        self.threads = resources.threads;

        resources.threads.runAsync(self, buildAsync);

        return .{ .data = .{ .TriangleMesh = mesh } };
    }

    pub fn loadData(
        self: *Provider,
        alloc: Allocator,
        data: *align(8) const anyopaque,
        options: Variants,
        resources: *Resources,
    ) !Shape {
        _ = options;

        const desc: *const Descriptor = @ptrCast(data);

        const num_parts = if (desc.num_parts > 0) desc.num_parts else 1;

        var mesh = try TriangleMesh.init(alloc, num_parts);

        if (desc.num_parts > 0 and null != desc.parts) {
            for (0..num_parts) |i| {
                mesh.setMaterialForPart(i, desc.parts.?[i * 3 + 2]);
            }
        } else {
            mesh.setMaterialForPart(0, 0);
        }

        resources.commitAsync();

        self.desc = desc.*;
        self.alloc = alloc;
        self.threads = resources.threads;

        resources.threads.runAsync(self, buildDescAsync);

        return Shape{ .TriangleMesh = mesh };
    }

    fn buildAsync(context: ThreadContext) void {
        const self: *Provider = @ptrCast(@alignCast(context));

        const handler = self.handler;

        const vertices = tvb.Buffer{ .Separate = tvb.Separate.init(
            handler.positions.items,
            handler.normals.items,
            handler.tangents.items,
            handler.uvs.items,
            handler.bitangent_signs.items,
        ) };

        buildBVH(self.alloc, &self.tree, self.handler.triangles.items, vertices, self.threads) catch {};

        self.handler.deinit(self.alloc);
    }

    fn loadGeometry(alloc: Allocator, handler: *Handler, value: std.json.Value) !void {
        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "parts", entry.key_ptr.*)) {
                const parts = entry.value_ptr.array.items;

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
                var viter = entry.value_ptr.object.iterator();
                while (viter.next()) |ventry| {
                    if (std.mem.eql(u8, "positions", ventry.key_ptr.*)) {
                        const positions = ventry.value_ptr.array.items;
                        const num_positions = positions.len / 3;

                        handler.positions = try Handler.Vec3fs.initCapacity(alloc, num_positions);
                        try handler.positions.resize(alloc, num_positions);

                        for (handler.positions.items, 0..) |*p, i| {
                            p.* = Pack3f.init3(
                                json.readFloat(f32, positions[i * 3 + 0]),
                                json.readFloat(f32, positions[i * 3 + 1]),
                                json.readFloat(f32, positions[i * 3 + 2]),
                            );
                        }
                    } else if (std.mem.eql(u8, "normals", ventry.key_ptr.*)) {
                        const normals = ventry.value_ptr.array.items;
                        const num_normals = normals.len / 3;

                        handler.normals = try Handler.Vec3fs.initCapacity(alloc, num_normals);
                        try handler.normals.resize(alloc, num_normals);

                        for (handler.normals.items, 0..) |*n, i| {
                            n.* = Pack3f.init3(
                                json.readFloat(f32, normals[i * 3 + 0]),
                                json.readFloat(f32, normals[i * 3 + 1]),
                                json.readFloat(f32, normals[i * 3 + 2]),
                            );
                        }
                    } else if (std.mem.eql(u8, "tangents_and_bitangent_signs", ventry.key_ptr.*)) {
                        const tangents = ventry.value_ptr.array.items;
                        const num_tangents = tangents.len / 4;

                        handler.tangents = try Handler.Vec3fs.initCapacity(alloc, num_tangents);
                        try handler.tangents.resize(alloc, num_tangents);

                        handler.bitangent_signs = try Handler.u8s.initCapacity(alloc, num_tangents);
                        try handler.bitangent_signs.resize(alloc, num_tangents);

                        for (handler.tangents.items, 0..) |*t, i| {
                            t.* = Pack3f.init3(
                                json.readFloat(f32, tangents[i * 4 + 0]),
                                json.readFloat(f32, tangents[i * 4 + 1]),
                                json.readFloat(f32, tangents[i * 4 + 2]),
                            );

                            handler.bitangent_signs.items[i] = if (json.readFloat(f32, tangents[i * 4 + 3]) >= 0.0) 0 else 1;
                        }
                    } else if (std.mem.eql(u8, "tangent_space", ventry.key_ptr.*)) {
                        log.warning("It is reading tangent space", .{});
                        const tangent_spaces = ventry.value_ptr.array.items;
                        const num_tangent_spaces = tangent_spaces.len / 4;

                        handler.normals = try Handler.Vec3fs.initCapacity(alloc, num_tangent_spaces);
                        try handler.normals.resize(alloc, num_tangent_spaces);

                        handler.tangents = try Handler.Vec3fs.initCapacity(alloc, num_tangent_spaces);
                        try handler.tangents.resize(alloc, num_tangent_spaces);

                        handler.bitangent_signs = try Handler.u8s.initCapacity(alloc, num_tangent_spaces);
                        try handler.bitangent_signs.resize(alloc, num_tangent_spaces);

                        for (handler.normals.items, 0..) |*n, i| {
                            var ts = Quaternion{
                                json.readFloat(f32, tangent_spaces[i * 4 + 0]),
                                json.readFloat(f32, tangent_spaces[i * 4 + 1]),
                                json.readFloat(f32, tangent_spaces[i * 4 + 2]),
                                json.readFloat(f32, tangent_spaces[i * 4 + 3]),
                            };

                            var bts = false;

                            if (ts[3] < 0.0) {
                                ts[3] = -ts[3];
                                bts = true;
                            }

                            const tbn = quaternion.toMat3x3(ts);
                            n.* = math.vec4fTo3f(tbn.r[2]);
                            const t = &handler.tangents.items[i];
                            t.* = math.vec4fTo3f(tbn.r[0]);

                            handler.bitangent_signs.items[i] = if (bts) 1 else 0;
                        }
                    } else if (std.mem.eql(u8, "texture_coordinates_0", ventry.key_ptr.*)) {
                        const uvs = ventry.value_ptr.array.items;
                        const num_uvs = uvs.len / 2;

                        handler.uvs = try Handler.Vec2fs.initCapacity(alloc, num_uvs);
                        try handler.uvs.resize(alloc, num_uvs);

                        for (handler.uvs.items, 0..) |*uv, i| {
                            uv.* = .{
                                json.readFloat(f32, uvs[i * 2 + 0]),
                                json.readFloat(f32, uvs[i * 2 + 1]),
                            };
                        }
                    }
                }
            } else if (std.mem.eql(u8, "indices", entry.key_ptr.*)) {
                const indices = entry.value_ptr.array.items;
                const num_triangles = indices.len / 3;

                handler.triangles = try Handler.Triangles.initCapacity(alloc, num_triangles);
                try handler.triangles.resize(alloc, num_triangles);

                for (handler.triangles.items, 0..) |*t, i| {
                    t.i[0] = @intCast(indices[i * 3 + 0].integer);
                    t.i[1] = @intCast(indices[i * 3 + 1].integer);
                    t.i[2] = @intCast(indices[i * 3 + 2].integer);
                    t.part = 0;
                }
            }
        }
    }

    fn loadBinary(self: *Provider, alloc: Allocator, stream: ReadStream, resources: *Resources) !TriangleMesh {
        try stream.seekTo(4);

        var parts: []Part = &.{};

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

            var json_strlen = json_size;
            while (0 == json_string[json_strlen - 1]) {
                json_strlen -= 1;
            }

            var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json_string[0..json_strlen], .{});
            defer parsed.deinit();

            const root = parsed.value;

            const geometry_node = root.object.get("geometry") orelse return Error.NoGeometryNode;

            var iter = geometry_node.object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "parts", entry.key_ptr.*)) {
                    const parts_slice = entry.value_ptr.array.items;

                    parts = try alloc.alloc(Part, parts_slice.len);

                    for (parts_slice, 0..) |p, i| {
                        parts[i].start_index = json.readUIntMember(p, "start_index", 0);
                        parts[i].num_indices = json.readUIntMember(p, "num_indices", 0);
                        parts[i].material_index = json.readUIntMember(p, "material_index", 0);
                    }
                } else if (std.mem.eql(u8, "vertices", entry.key_ptr.*)) {
                    var viter = entry.value_ptr.object.iterator();
                    while (viter.next()) |vn| {
                        if (std.mem.eql(u8, "binary", vn.key_ptr.*)) {
                            vertices_offset = json.readUInt64Member(vn.value_ptr.*, "offset", 0);
                            vertices_size = json.readUInt64Member(vn.value_ptr.*, "size", 0);
                        } else if (std.mem.eql(u8, "num_vertices", vn.key_ptr.*)) {
                            num_vertices = json.readUInt(vn.value_ptr.*);
                        } else if (std.mem.eql(u8, "layout", vn.key_ptr.*)) {
                            for (vn.value_ptr.array.items) |ln| {
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
                    var iiter = entry.value_ptr.object.iterator();
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

        const has_uvs_and_tangents = has_uvs and has_tangents;

        const binary_start = json_size + 4 + @sizeOf(u64);

        if (0 == num_vertices) {
            // Handle legacy files, that curiously worked because of Gzip_stream bug!
            // (seekg() was not implemented properly)
            const Sizeof_vertex = 48;
            num_vertices = @intCast(vertices_size / Sizeof_vertex);

            if (!interleaved_vertex_stream) {
                const Vertex_unpadded_size = 3 * 4 + 3 * 4 + 3 * 4 + 2 * 4 + 1;
                indices_offset = num_vertices * Vertex_unpadded_size;
            }
        }

        try stream.seekTo(binary_start + vertices_offset);

        var vertices: tvb.Buffer = undefined;

        if (interleaved_vertex_stream) {
            log.err("interleaved", .{});
        } else {
            const positions = try alloc.alloc(Pack3f, num_vertices);
            _ = try stream.read(std.mem.sliceAsBytes(positions));

            if (tangent_space_as_quaternion) {
                const ts = try alloc.alloc(Pack4f, num_vertices);
                _ = try stream.read(std.mem.sliceAsBytes(ts));

                const uvs = try alloc.alloc(Vec2f, num_vertices);
                _ = try stream.read(std.mem.sliceAsBytes(uvs));

                vertices = tvb.Buffer{ .SeparateQuat = tvb.SeparateQuat.init(
                    positions,
                    ts,
                    uvs,
                ) };
            } else {
                const normals = try alloc.alloc(Pack3f, num_vertices);
                _ = try stream.read(std.mem.sliceAsBytes(normals));

                if (has_uvs_and_tangents) {
                    const tangents = try alloc.alloc(Pack3f, num_vertices);
                    _ = try stream.read(std.mem.sliceAsBytes(tangents));

                    const uvs = try alloc.alloc(Vec2f, num_vertices);
                    _ = try stream.read(std.mem.sliceAsBytes(uvs));

                    const bts = try alloc.alloc(u8, num_vertices);
                    _ = try stream.read(bts);

                    vertices = tvb.Buffer{ .Separate = tvb.Separate.initOwned(
                        positions,
                        normals,
                        tangents,
                        uvs,
                        bts,
                    ) };
                } else {
                    vertices = tvb.Buffer{ .Separate = tvb.Separate.initOwned(
                        positions,
                        normals,
                        &.{},
                        &.{},
                        &.{},
                    ) };
                }
            }
        }

        if (0 == num_indices) {
            num_indices = @intCast(indices_size / index_bytes);
        }

        try stream.seekTo(binary_start + indices_offset);

        const indices = try alloc.alloc(u8, indices_size);

        _ = try stream.read(indices);

        var mesh = try TriangleMesh.init(alloc, @intCast(parts.len));

        for (parts, 0..) |p, i| {
            if (p.start_index + p.num_indices > num_indices) {
                return Error.PartIndicesOutOfBounds;
            }

            mesh.setMaterialForPart(i, p.material_index);
        }

        resources.commitAsync();

        self.num_indices = num_indices;
        self.index_bytes = index_bytes;
        self.delta_indices = delta_indices;
        self.parts = parts;
        self.indices = indices;
        self.vertices = vertices;
        self.indices = indices;
        self.alloc = alloc;
        self.threads = resources.threads;

        resources.threads.runAsync(self, buildBinaryAsync);

        return mesh;
    }

    fn buildBinaryAsync(context: ThreadContext) void {
        const self: *Provider = @ptrCast(@alignCast(context));

        const num_triangles = self.num_indices / 3;
        const triangles = self.alloc.alloc(IndexTriangle, num_triangles) catch unreachable;
        defer self.alloc.free(triangles);

        if (4 == self.index_bytes) {
            if (self.delta_indices) {
                fillTrianglesDelta(i32, self.parts, self.indices, triangles);
            } else {
                fillTriangles(u32, self.parts, self.indices, triangles);
            }
        } else {
            if (self.delta_indices) {
                fillTrianglesDelta(i16, self.parts, self.indices, triangles);
            } else {
                fillTriangles(u16, self.parts, self.indices, triangles);
            }
        }

        buildBVH(self.alloc, &self.tree, triangles, self.vertices, self.threads) catch {};

        self.alloc.free(self.indices);
        self.alloc.free(self.parts);
        self.vertices.deinit(self.alloc);
    }

    fn buildDescAsync(context: ThreadContext) void {
        const self: *Provider = @ptrCast(@alignCast(context));

        const num_triangles = self.desc.num_primitives;
        var triangles = self.alloc.alloc(IndexTriangle, num_triangles) catch unreachable;
        defer self.alloc.free(triangles);

        var desc = self.desc;

        if (null == desc.tangents) {
            desc.tangents_stride = 0;
        }

        if (null == desc.uvs) {
            desc.uvs_stride = 0;
        }

        const empty_part = [3]u32{ 0, num_triangles * 3, 0 };
        const parts = if (desc.num_parts > 0 and null != desc.parts) desc.parts.? else &empty_part;

        const num_parts = if (desc.num_parts > 0) desc.num_parts else 1;
        var p: u32 = 0;
        while (p < num_parts) : (p += 1) {
            const start_index = parts[p * 3 + 0];
            const num_indices = parts[p * 3 + 1];

            const triangles_start = start_index / 3;
            const triangles_end = (start_index + num_indices) / 3;

            var i = triangles_start;
            if (desc.indices) |indices| {
                while (i < triangles_end) : (i += 1) {
                    const t = i * 3;
                    triangles[i].i[0] = indices[t + 0];
                    triangles[i].i[1] = indices[t + 1];
                    triangles[i].i[2] = indices[t + 2];

                    triangles[i].part = p;
                }
            } else {
                while (i < triangles_end) : (i += 1) {
                    const t = i * 3;
                    triangles[i].i[0] = t + 0;
                    triangles[i].i[1] = t + 1;
                    triangles[i].i[2] = t + 2;

                    triangles[i].part = p;
                }
            }
        }

        const null_floats = [_]f32{ 0.0, 0.0, 0.0, 0.0 };

        const vertices = tvb.Buffer{ .C = tvb.CAPI.init(
            desc.num_vertices,
            desc.positions_stride,
            desc.normals_stride,
            desc.tangents_stride,
            desc.uvs_stride,
            desc.positions,
            desc.normals,
            if (desc.tangents) |tangents| tangents else &null_floats,
            if (desc.uvs) |uvs| uvs else &null_floats,
        ) };

        buildBVH(self.alloc, &self.tree, triangles, vertices, self.threads) catch {};
    }

    fn buildBVH(
        alloc: Allocator,
        tree: *TriangleTree,
        triangles: []const IndexTriangle,
        vertices: tvb.Buffer,
        threads: *Threads,
    ) !void {
        var builder = try TriangleBuilder.init(alloc, 16, 64, 4);
        defer builder.deinit(alloc);

        try builder.build(alloc, tree, triangles, vertices, threads);
    }

    fn fillTriangles(
        comptime I: type,
        parts: []const Part,
        index_buffer: []const u8,
        triangles: []IndexTriangle,
    ) void {
        const indices = std.mem.bytesAsSlice(I, index_buffer);

        for (parts, 0..) |p, i| {
            const triangles_start = p.start_index / 3;
            const triangles_end = (p.start_index + p.num_indices) / 3;

            for (triangles[triangles_start..triangles_end], triangles_start..) |*t, j| {
                t.i[0] = @intCast(indices[j * 3 + 0]);
                t.i[1] = @intCast(indices[j * 3 + 1]);
                t.i[2] = @intCast(indices[j * 3 + 2]);

                t.part = @intCast(i);
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

        for (parts, 0..) |p, i| {
            const triangles_start = p.start_index / 3;
            const triangles_end = (p.start_index + p.num_indices) / 3;

            for (triangles[triangles_start..triangles_end], triangles_start..) |*t, j| {
                const a = previous_index + @as(i32, @intCast(indices[j * 3 + 0]));
                t.i[0] = @intCast(a);

                const b = a + @as(i32, @intCast(indices[j * 3 + 1]));
                t.*.i[1] = @intCast(b);

                const c = b + @as(i32, @intCast(indices[j * 3 + 2]));
                t.i[2] = @intCast(c);

                t.part = @intCast(i);

                previous_index = c;
            }
        }
    }
};
