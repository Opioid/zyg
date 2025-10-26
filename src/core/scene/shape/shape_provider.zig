const log = @import("../../log.zig");
const Shape = @import("shape.zig").Shape;
const CurveMesh = @import("curve/curve_mesh.zig").Mesh;
const PointMotionCloud = @import("point/point_motion_cloud.zig").MotionCloud;
const PointMotionTreeBuilder = @import("point/point_motion_tree_builder.zig").Builder;
const TriangleMesh = @import("triangle/triangle_mesh.zig").Mesh;
const TriangleMotionMesh = @import("triangle/triangle_motion_mesh.zig").MotionMesh;
const tvb = @import("triangle/vertex_buffer.zig");
const TriangleTree = @import("triangle/triangle_tree.zig").Tree;
const TriangleMotionTree = @import("triangle/triangle_motion_tree.zig").Tree;
const TriangleBuilder = @import("triangle/triangle_tree_builder.zig").Builder;
const IndexTriangle = TriangleBuilder.IndexTriangle;
const CurveBuilder = @import("curve/curve_tree_builder.zig").Builder;
const HairReader = @import("curve/hair_reader.zig").Reader;
const Resources = @import("../../resource/manager.zig").Manager;
const Result = @import("../../resource/result.zig").Result;
const Scene = @import("../../scene/Scene.zig").Scene;
const motion = @import("../../scene/motion.zig");
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

const std = @import("std");
const Allocator = std.mem.Allocator;

const Part = struct {
    start_index: u32,
    num_indices: u32,
    material_index: u32,
};

const Handler = struct {
    pub const Topology = enum {
        PointList,
        TriangleList,
    };

    topology: Topology = .TriangleList,
    frame_duration: u64 = 0,
    start_frame: u32 = 0,
    point_radius: f32 = 0.0,
    parts: []Part = &.{},
    triangles: []IndexTriangle = &.{},
    positions: [][]Pack3f = &.{},
    normals: []Pack3f = &.{},
    uvs: []Vec2f = &.{},
    radii: [][]f32 = &.{},

    pub fn deinit(self: *Handler, alloc: Allocator) void {
        for (self.radii) |r| {
            alloc.free(r);
        }
        alloc.free(self.radii);

        alloc.free(self.uvs);
        alloc.free(self.normals);

        for (self.positions) |p| {
            alloc.free(p);
        }
        alloc.free(self.positions);

        alloc.free(self.triangles);
        alloc.free(self.parts);
    }
};

const Error = error{
    NoGeometryNode,
    NoVertices,
    NoTriangles,
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

    frame_duration: u64 = 0,
    start_frame: u32 = 0,

    num_indices: u32 = undefined,
    index_bytes: u64 = undefined,
    delta_indices: bool = undefined,
    handler: Handler = undefined,
    triangle_tree: TriangleTree = .{},
    triangle_motion_tree: TriangleMotionTree = .{},
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
        if (0 == self.triangle_tree.nodes.len and 0 == self.triangle_motion_tree.nodes.len) {
            return;
        }

        if (resources.shapes.getLatest()) |latest| {
            switch (latest.*) {
                .TriangleMesh => |*m| {
                    std.mem.swap(TriangleTree, &m.tree, &self.triangle_tree);
                    m.calculateAreas();
                },
                .TriangleMotionMesh => |*m| {
                    std.mem.swap(TriangleMotionTree, &m.tree, &self.triangle_motion_tree);
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

            const file_type = try file.queryType(stream);

            if (file.Type.HAIR == file_type) {
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
            } else if (file.Type.SUB == file_type) {
                const mesh = self.loadBinary(alloc, stream, resources) catch |e| {
                    log.err("Loading mesh \"{s}\": {}", .{ name, e });
                    return e;
                };

                return .{ .data = mesh };
            }

            const buffer = try stream.readAlloc(alloc);
            defer alloc.free(buffer);

            var parsed = std.json.parseFromSlice(std.json.Value, alloc, buffer, .{}) catch |e| {
                log.err("Loading mesh \"{s}\": {}", .{ name, e });
                return e;
            };
            defer parsed.deinit();

            const root = parsed.value;

            if (root.object.get("geometry")) |value| {
                try loadGeometry(alloc, &handler, value, resources);
            }
        }

        if (0 == handler.positions.len) {
            return Error.NoVertices;
        }

        if (.PointList == handler.topology) {
            var cloud = PointMotionCloud{};

            cloud.tree.data.frame_duration = @intCast(handler.frame_duration);
            cloud.tree.data.start_frame = handler.start_frame;

            var builder = try PointMotionTreeBuilder.init(alloc);
            defer builder.deinit(alloc);

            try builder.build(
                alloc,
                &cloud.tree,
                handler.point_radius,
                handler.positions,
                handler.radii,
                resources.threads,
            );

            handler.deinit(alloc);

            resources.commitAsync();

            return .{ .data = .{ .PointMotionCloud = cloud } };
        } else {
            if (0 == handler.triangles.len) {
                return Error.NoTriangles;
            }

            for (handler.parts, 0..) |p, i| {
                const triangles_start = p.start_index / 3;
                const triangles_end = (p.start_index + p.num_indices) / 3;

                for (handler.triangles[triangles_start..triangles_end]) |*t| {
                    t.part = @intCast(i);
                }
            }

            if (handler.positions.len > 1) {
                var mesh = try TriangleMotionMesh.init(alloc, @intCast(handler.parts.len));

                for (handler.parts, 0..) |p, i| {
                    mesh.setMaterialForPart(i, p.material_index);
                }

                resources.commitAsync();

                self.handler = handler;
                self.alloc = alloc;
                self.threads = resources.threads;

                resources.threads.runAsync(self, buildAsync);

                return .{ .data = .{ .TriangleMotionMesh = mesh } };
            } else {
                var mesh = try TriangleMesh.init(alloc, @intCast(handler.parts.len));

                for (handler.parts, 0..) |p, i| {
                    mesh.setMaterialForPart(i, p.material_index);
                }

                resources.commitAsync();

                self.handler = handler;
                self.alloc = alloc;
                self.threads = resources.threads;

                resources.threads.runAsync(self, buildAsync);

                return .{ .data = .{ .TriangleMesh = mesh } };
            }
        }
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

        const vertices = tvb.Buffer{ .Separate = tvb.Separate.init(
            self.handler.positions,
            self.handler.normals,
            self.handler.uvs,
        ) };

        if (self.handler.positions.len > 1) {
            buildMotionBVH(
                self.alloc,
                &self.triangle_motion_tree,
                self.handler.triangles,
                vertices,
                self.handler.frame_duration,
                self.handler.start_frame,
                self.threads,
            ) catch {};
        } else {
            buildBVH(self.alloc, &self.triangle_tree, self.handler.triangles, vertices, self.threads) catch {};
        }

        self.handler.deinit(self.alloc);
    }

    fn loadGeometry(alloc: Allocator, handler: *Handler, value: std.json.Value, resources: *Resources) !void {
        const fps = json.readFloatMember(value, "frames_per_second", 60.0);

        const animation_frame_duration: u64 = @intFromFloat(@round(@as(f64, @floatFromInt(Scene.UnitsPerSecond)) / fps));

        handler.frame_duration = animation_frame_duration;

        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "primitive_topology", entry.key_ptr.*)) {
                if (std.mem.eql(u8, "point_list", entry.value_ptr.string)) {
                    handler.topology = .PointList;
                } else if (std.mem.eql(u8, "triangle_list", entry.value_ptr.string)) {
                    handler.topology = .TriangleList;
                }
            } else if (std.mem.eql(u8, "point_radius", entry.key_ptr.*)) {
                handler.point_radius = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "parts", entry.key_ptr.*)) {
                const parts = entry.value_ptr.array.items;

                handler.parts = try alloc.alloc(Part, parts.len);

                for (parts, 0..) |p, i| {
                    const start_index = json.readUIntMember(p, "start_index", 0);
                    const num_indices = json.readUIntMember(p, "num_indices", 0);
                    const material_index = json.readUIntMember(p, "material_index", 0);
                    handler.parts[i] = .{
                        .start_index = start_index,
                        .num_indices = num_indices,
                        .material_index = material_index,
                    };
                }
            } else if (std.mem.eql(u8, "vertices", entry.key_ptr.*)) {
                var viter = entry.value_ptr.object.iterator();
                while (viter.next()) |ventry| {
                    if (std.mem.eql(u8, "positions", ventry.key_ptr.*)) {
                        const position_items = ventry.value_ptr.array.items;

                        switch (position_items[0]) {
                            .array => {
                                const position_samples = position_items;
                                const num_frames = position_samples.len;

                                const start_frame = @min(resources.frame_start / animation_frame_duration, num_frames - 1);
                                const counted_frames = motion.countFrames(resources.frame_duration, animation_frame_duration);
                                const end_frame = @min(start_frame + counted_frames + 1, num_frames);

                                handler.positions = try alloc.alloc([]Pack3f, end_frame - start_frame);

                                for (position_samples[start_frame..end_frame], 0..) |frame, f| {
                                    const positions = frame.array.items;
                                    const num_positions = positions.len / 3;

                                    const dest_positions = try alloc.alloc(Pack3f, num_positions);

                                    for (dest_positions, 0..) |*p, i| {
                                        p.* = Pack3f.init3(
                                            json.readFloat(f32, positions[i * 3 + 0]),
                                            json.readFloat(f32, positions[i * 3 + 1]),
                                            json.readFloat(f32, positions[i * 3 + 2]),
                                        );
                                    }

                                    handler.positions[f] = dest_positions;
                                }

                                handler.start_frame = @intCast(start_frame);
                            },
                            .integer, .float => {
                                const positions = position_items;
                                const num_positions = positions.len / 3;

                                const dest_positions = try alloc.alloc(Pack3f, num_positions);

                                for (dest_positions, 0..) |*p, i| {
                                    p.* = Pack3f.init3(
                                        json.readFloat(f32, positions[i * 3 + 0]),
                                        json.readFloat(f32, positions[i * 3 + 1]),
                                        json.readFloat(f32, positions[i * 3 + 2]),
                                    );
                                }

                                handler.positions = try alloc.alloc([]Pack3f, 1);
                                handler.positions[0] = dest_positions;
                                handler.start_frame = 0;
                            },
                            else => {},
                        }
                    } else if (std.mem.eql(u8, "normals", ventry.key_ptr.*)) {
                        const normal_items = ventry.value_ptr.array.items;

                        switch (normal_items[0]) {
                            .array => {
                                const num_frames = normal_items.len;
                                const start_frame = @min(resources.frame_start / animation_frame_duration, num_frames - 1);

                                const normals = normal_items[start_frame].array.items;
                                const num_normals = normals.len / 3;

                                handler.normals = try alloc.alloc(Pack3f, num_normals);

                                for (handler.normals, 0..) |*n, i| {
                                    n.* = Pack3f.init3(
                                        json.readFloat(f32, normals[i * 3 + 0]),
                                        json.readFloat(f32, normals[i * 3 + 1]),
                                        json.readFloat(f32, normals[i * 3 + 2]),
                                    );
                                }
                            },
                            .integer, .float => {
                                const normals = normal_items;
                                const num_normals = normals.len / 3;

                                handler.normals = try alloc.alloc(Pack3f, num_normals);

                                for (handler.normals, 0..) |*n, i| {
                                    n.* = Pack3f.init3(
                                        json.readFloat(f32, normals[i * 3 + 0]),
                                        json.readFloat(f32, normals[i * 3 + 1]),
                                        json.readFloat(f32, normals[i * 3 + 2]),
                                    );
                                }
                            },
                            else => {},
                        }
                    } else if (std.mem.eql(u8, "tangent_space", ventry.key_ptr.*)) {
                        const tangent_spaces = ventry.value_ptr.array.items;
                        const num_tangent_spaces = tangent_spaces.len / 4;

                        handler.normals = try alloc.alloc(Pack3f, num_tangent_spaces);

                        for (handler.normals, 0..) |*n, i| {
                            const ts = Quaternion{
                                json.readFloat(f32, tangent_spaces[i * 4 + 0]),
                                json.readFloat(f32, tangent_spaces[i * 4 + 1]),
                                json.readFloat(f32, tangent_spaces[i * 4 + 2]),
                                json.readFloat(f32, tangent_spaces[i * 4 + 3]),
                            };

                            const tbn = quaternion.toMat3x3(ts);
                            n.* = math.vec4fTo3f(tbn.r[2]);
                        }
                    } else if (std.mem.eql(u8, "texture_coordinates_0", ventry.key_ptr.*)) {
                        const uvs = ventry.value_ptr.array.items;
                        const num_uvs = uvs.len / 2;

                        handler.uvs = try alloc.alloc(Vec2f, num_uvs);

                        for (handler.uvs, 0..) |*uv, i| {
                            uv.* = .{
                                json.readFloat(f32, uvs[i * 2 + 0]),
                                json.readFloat(f32, uvs[i * 2 + 1]),
                            };
                        }
                    } else if (std.mem.eql(u8, "radius_samples", ventry.key_ptr.*)) {
                        const radius_samples = ventry.value_ptr.array.items;
                        const num_frames = radius_samples.len;

                        const start_frame = @min(resources.frame_start / animation_frame_duration, num_frames - 1);
                        const counted_frames = motion.countFrames(resources.frame_duration, animation_frame_duration);
                        const end_frame = @min(start_frame + counted_frames + 1, num_frames);

                        handler.radii = try alloc.alloc([]f32, end_frame - start_frame);

                        for (radius_samples[start_frame..end_frame], 0..) |frame, f| {
                            const radii = frame.array.items;

                            const dest_radii = try alloc.alloc(f32, radii.len);

                            for (dest_radii, 0..) |*r, i| {
                                r.* = json.readFloat(f32, radii[i]);
                            }

                            handler.radii[f] = dest_radii;
                        }
                    }
                }
            } else if (std.mem.eql(u8, "indices", entry.key_ptr.*)) {
                const indices = entry.value_ptr.array.items;
                const num_triangles = indices.len / 3;

                handler.triangles = try alloc.alloc(IndexTriangle, num_triangles);

                for (handler.triangles, 0..) |*t, i| {
                    t.i[0] = @intCast(indices[i * 3 + 0].integer);
                    t.i[1] = @intCast(indices[i * 3 + 1].integer);
                    t.i[2] = @intCast(indices[i * 3 + 2].integer);
                    t.part = 0;
                }
            }
        }
    }

    fn loadBinary(self: *Provider, alloc: Allocator, stream: ReadStream, resources: *Resources) !Shape {
        try stream.discard(4);

        var frame_duration: u64 = 0;

        var parts: []Part = &.{};

        var vertices_offset: u64 = 0;
        var vertices_size: u64 = 0;

        var indices_offset: u64 = 0;
        var indices_size: u64 = 0;
        var index_bytes: u64 = 0;

        var num_vertices: u32 = 0;
        var num_indices: u32 = 0;

        var num_position_frames: u32 = 1;
        var num_normal_frames: u32 = 1;

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
                if (std.mem.eql(u8, "frame_duration", entry.key_ptr.*)) {
                    frame_duration = json.readUInt64(entry.value_ptr.*);
                } else if (std.mem.eql(u8, "parts", entry.key_ptr.*)) {
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
                                if (std.mem.eql(u8, "Position", semantic_name)) {
                                    num_position_frames = json.readUIntMember(ln, "num_frames", 1);
                                } else if (std.mem.eql(u8, "Normal", semantic_name)) {
                                    num_normal_frames = json.readUIntMember(ln, "num_frames", 1);
                                } else if (std.mem.eql(u8, "Tangent", semantic_name)) {
                                    has_tangents = true;
                                } else if (std.mem.eql(u8, "Tangent_space", semantic_name)) {
                                    tangent_space_as_quaternion = true;
                                } else if (std.mem.eql(u8, "TextureCoordinate", semantic_name) or std.mem.eql(u8, "Texture_coordinate", semantic_name)) {
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
            const SizeofVertex = 48;
            num_vertices = @intCast(vertices_size / SizeofVertex);

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
            const start_frame = @min(if (0 == frame_duration) 0 else resources.frame_start / frame_duration, num_position_frames - 1);
            const counted_frames = motion.countFrames(resources.frame_duration, frame_duration);
            const end_frame = start_frame + @min(start_frame + counted_frames + 1, num_position_frames);

            const positions = try alloc.alloc([]Pack3f, end_frame - start_frame);

            if (start_frame > 0) {
                try stream.discard(@sizeOf(Pack3f) * num_vertices * start_frame);
            }

            for (0..positions.len) |f| {
                positions[f] = try alloc.alloc(Pack3f, num_vertices);
                _ = try stream.read(std.mem.sliceAsBytes(positions[f]));
            }

            if (num_position_frames - end_frame > 0) {
                try stream.discard(@sizeOf(Pack3f) * num_vertices * (num_position_frames - end_frame));
            }

            self.start_frame = @intCast(start_frame);

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
                const start_normal_frame = @min(if (0 == frame_duration) 0 else resources.frame_start / frame_duration, num_normal_frames - 1);

                if (start_normal_frame > 0) {
                    try stream.discard(@sizeOf(Pack3f) * num_vertices * start_normal_frame);
                }

                const normals = try alloc.alloc(Pack3f, num_vertices);
                _ = try stream.read(std.mem.sliceAsBytes(normals));

                if ((num_normal_frames - start_normal_frame) > 1) {
                    try stream.discard(@sizeOf(Pack3f) * num_vertices * (num_normal_frames - start_normal_frame - 1));
                }

                if (has_uvs_and_tangents) {
                    try stream.discard(@sizeOf(Pack3f) * num_vertices);

                    const uvs = try alloc.alloc(Vec2f, num_vertices);
                    _ = try stream.read(std.mem.sliceAsBytes(uvs));

                    vertices = tvb.Buffer{ .Separate = tvb.Separate.initOwned(
                        positions,
                        normals,
                        uvs,
                    ) };
                } else if (has_uvs) {
                    const uvs = try alloc.alloc(Vec2f, num_vertices);
                    _ = try stream.read(std.mem.sliceAsBytes(uvs));

                    vertices = tvb.Buffer{ .Separate = tvb.Separate.initOwned(
                        positions,
                        normals,
                        uvs,
                    ) };
                } else {
                    vertices = tvb.Buffer{ .Separate = tvb.Separate.initOwned(
                        positions,
                        normals,
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

        var shape: Shape = undefined;

        if (vertices.numFrames() > 1) {
            var mesh = try TriangleMotionMesh.init(alloc, @intCast(parts.len));

            for (parts, 0..) |p, i| {
                if (p.start_index + p.num_indices > num_indices) {
                    return Error.PartIndicesOutOfBounds;
                }

                mesh.setMaterialForPart(i, p.material_index);
            }

            shape = .{ .TriangleMotionMesh = mesh };
        } else {
            var mesh = try TriangleMesh.init(alloc, @intCast(parts.len));

            for (parts, 0..) |p, i| {
                if (p.start_index + p.num_indices > num_indices) {
                    return Error.PartIndicesOutOfBounds;
                }

                mesh.setMaterialForPart(i, p.material_index);
            }

            shape = .{ .TriangleMesh = mesh };
        }

        resources.commitAsync();

        self.frame_duration = frame_duration;
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

        return shape;
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

        if (self.vertices.numFrames() > 1) {
            buildMotionBVH(
                self.alloc,
                &self.triangle_motion_tree,
                triangles,
                self.vertices,
                self.frame_duration,
                self.start_frame,
                self.threads,
            ) catch {};
        } else {
            buildBVH(self.alloc, &self.triangle_tree, triangles, self.vertices, self.threads) catch {};
        }

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

        buildBVH(self.alloc, &self.triangle_tree, triangles, vertices, self.threads) catch {};
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

    fn buildMotionBVH(
        alloc: Allocator,
        tree: *TriangleMotionTree,
        triangles: []const IndexTriangle,
        vertices: tvb.Buffer,
        frame_duration: u64,
        start_frame: u32,
        threads: *Threads,
    ) !void {
        var builder = try TriangleBuilder.init(alloc, 16, 64, 4);
        defer builder.deinit(alloc);

        try builder.buildMotion(alloc, tree, triangles, vertices, frame_duration, start_frame, threads);
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
