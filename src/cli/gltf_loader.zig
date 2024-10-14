const Graph = @import("scene_graph.zig").Graph;

const core = @import("core");
const cam = core.camera;
const scn = core.scn;
const Shape = scn.Shape;
const resource = core.resource;
const Resources = resource.Manager;
const ReadStream = core.file.ReadStream;

const base = @import("base");
const json = base.json;
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;
const Transformation = math.Transformation;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub const Loader = struct {
    const Error = error{
        PrimitivesMissing,
        AttributesMissing,
        IndexNoBuffer,
        IndexInvalidComponentType,
    };

    const Accessor = struct {
        const ComponentType = enum(u32) {
            UInt16 = 5123,
            UInt32 = 5125,
            Float32 = 5126,
        };

        buffer_view: u32,
        byte_offset: u32,
        component_type: ComponentType,
        count: u32,
    };

    const BufferView = struct {
        buffer: u32,
        byte_length: u32,
        byte_offset: u32,
        byte_stride: u32,
    };

    const Buffer = struct {
        uri: []const u8,
    };

    const MeshDescriptor = struct {
        indices: []u32 = undefined,
        positions: []f32 = undefined,
        normals: []f32 = undefined,
        tangents: ?[]f32 = null,
        uvs: ?[]f32 = null,
    };

    const Part = struct {
        start_index: u32,
        num_indices: u32,
        material_index: u32,
    };

    resources: *Resources,

    read_stream: ReadStream = undefined,
    read_stream_id: u32 = Null,

    fallback_material: u32,

    accessors: List(Accessor) = .empty,
    buffer_views: List(BufferView) = .empty,
    buffers: List(Buffer) = .empty,

    materials: List(u32) = .empty,

    material_map: std.AutoHashMapUnmanaged(u32, u32) = .empty,

    const Null = resource.Null;

    const Self = @This();

    pub fn init(resources: *Resources, fallback_material: u32) Self {
        return .{ .resources = resources, .fallback_material = fallback_material };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.closeStream();

        self.accessors.deinit(alloc);
        self.buffer_views.deinit(alloc);
        self.buffers.deinit(alloc);
        self.material_map.deinit(alloc);
    }

    pub fn load(
        self: *Self,
        alloc: Allocator,
        root: std.json.Value,
        parent_trafo: Transformation,
        graph: *Graph,
    ) !bool {
        if (root.object.get("asset")) |asset_node| {
            const version = json.readStringMember(asset_node, "version", "");
            const major = std.fmt.parseInt(i32, version[0..1], 0) catch 0;
            if (major < 2) {
                return false;
            }
        } else return false;

        if (root.object.get("accessors")) |node| {
            try self.accessors.ensureTotalCapacity(alloc, node.array.items.len);

            for (node.array.items) |n| {
                const accessor = Accessor{
                    .buffer_view = json.readUIntMember(n, "bufferView", 0),
                    .byte_offset = json.readUIntMember(n, "byteOffset", 0),
                    .component_type = @enumFromInt(json.readUIntMember(n, "componentType", 0)),
                    .count = json.readUIntMember(n, "count", 0),
                };

                self.accessors.appendAssumeCapacity(accessor);
            }
        }

        if (root.object.get("bufferViews")) |node| {
            try self.buffer_views.ensureTotalCapacity(alloc, node.array.items.len);

            for (node.array.items) |n| {
                const buffer_view = BufferView{
                    .buffer = json.readUIntMember(n, "buffer", 0),
                    .byte_length = json.readUIntMember(n, "byteLength", 0),
                    .byte_offset = json.readUIntMember(n, "byteOffset", 0),
                    .byte_stride = json.readUIntMember(n, "byteStride", 0),
                };

                self.buffer_views.appendAssumeCapacity(buffer_view);
            }
        }

        if (root.object.get("buffers")) |node| {
            try self.buffers.ensureTotalCapacity(alloc, node.array.items.len);

            for (node.array.items) |n| {
                const buffer = Buffer{
                    .uri = json.readStringMember(n, "uri", ""),
                };

                self.buffers.appendAssumeCapacity(buffer);
            }
        }

        if (root.object.get("materials")) |node| {
            const global_scale = parent_trafo.scale[0];

            for (node.array.items) |n| {
                const material_id = self.loadMaterial(alloc, n, root, global_scale) catch Null;
                try self.materials.append(alloc, material_id);
            }
        }

        if (root.object.get("nodes")) |nodes_node| {
            for (nodes_node.array.items) |n| {
                try self.loadNode(alloc, n, root, parent_trafo, graph);
            }
        } else return false;

        return true;
    }

    fn closeStream(self: *Self) void {
        if (Null != self.read_stream_id) {
            self.read_stream.deinit();
        }
    }

    fn readStream(self: *Self, alloc: Allocator, index: u32) !ReadStream {
        if (index == self.read_stream_id) {
            return self.read_stream;
        } else {
            self.closeStream();

            const buffer = self.buffers.items[index];

            self.read_stream = try self.resources.fs.readStream(alloc, buffer.uri);
            self.read_stream_id = index;

            return self.read_stream;
        }
    }

    fn loadNode(
        self: *Self,
        alloc: Allocator,
        value: std.json.Value,
        root: std.json.Value,
        parent_trafo: Transformation,
        graph: *Graph,
    ) !void {
        const translation = json.readVec4f3Member(value, "translation", @splat(0.0));
        const rotation = json.readVec4fMember(value, "rotation", math.quaternion.identity);
        const scale = json.readVec4f3Member(value, "scale", @splat(1.0));

        const trafo = Transformation{
            .position = .{ translation[0], translation[1], -translation[2], 0.0 },
            .scale = scale,
            .rotation = .{ rotation[0], rotation[1], -rotation[2], rotation[3] },
        };

        if (value.object.get("camera")) |camera_node| {
            const index = json.readUInt(camera_node);

            const cameras = root.object.get("cameras") orelse return;
            const camera = cameras.array.items[index];

            if (camera.object.get("perspective")) |perspective_node| {
                var pc = cam.Perspective{};

                var resolution = Vec2i{ 1280, 720 };
                if (graph.take.view.cameras.items.len > 0) {
                    resolution = graph.take.view.cameras.items[0].resolution;
                }

                pc.setResolution(resolution, .{ 0, 0, resolution[0], resolution[1] });

                const fr: Vec2f = @floatFromInt(resolution);
                const ratio = fr[0] / fr[1];

                const yfov = json.readFloatMember(perspective_node, "yfov", 0.5);
                pc.fov = ratio * yfov;

                const entity_id = try graph.scene.createEntity(alloc);

                const world_trafo = parent_trafo.transform(trafo);
                graph.scene.propSetWorldTransformation(entity_id, world_trafo);

                pc.entity = entity_id;

                try graph.take.view.cameras.append(alloc, pc);
            }
        } else if (value.object.get("mesh")) |mesh_node| {
            const index = json.readUInt(mesh_node);

            const meshes = root.object.get("meshes") orelse return;
            const mesh = meshes.array.items[index];
            const entity_id = try self.loadMesh(alloc, mesh, graph);

            const world_trafo = parent_trafo.transformScaled(trafo);

            graph.scene.propSetWorldTransformation(entity_id, world_trafo);
        }
    }

    fn mappedMaterialIndex(self: *Self, alloc: Allocator, gltf_id: u32, graph: *Graph) !u32 {
        if (self.material_map.get(gltf_id)) |index| {
            return index;
        }

        const renderer_id = if (gltf_id < self.materials.items.len) self.materials.items[gltf_id] else Null;

        if (Null != renderer_id) {
            try graph.materials.append(alloc, renderer_id);
        } else {
            try graph.materials.append(alloc, self.fallback_material);
        }

        const index: u32 = @intCast(graph.materials.items.len - 1);

        try self.material_map.put(alloc, gltf_id, index);

        return index;
    }

    fn loadMesh(self: *Self, alloc: Allocator, mesh: std.json.Value, graph: *Graph) !u32 {
        const prim_node = mesh.object.get("primitives") orelse return Error.PrimitivesMissing;

        var num_indices: u32 = 0;
        var num_vertices: u32 = 0;
        var has_tangents = false;
        var has_uvs = false;

        for (prim_node.array.items) |p| {
            const index_id = json.readUIntMember(p, "indices", Null);

            if (Null == index_id) {
                return Error.IndexNoBuffer;
            }

            const attributes = p.object.get("attributes") orelse return Error.AttributesMissing;

            const position_id = json.readUIntMember(attributes, "POSITION", Null);
            const tangent_id = json.readUIntMember(attributes, "TANGENT", Null);
            const uv_id = json.readUIntMember(attributes, "TEXCOORD_0", Null);

            const index_acc = self.accessors.items[index_id];
            num_indices += index_acc.count;

            const pos_acc = self.accessors.items[position_id];
            num_vertices += pos_acc.count;

            has_tangents = has_tangents or Null != tangent_id;
            has_uvs = has_uvs or Null != uv_id;
        }

        graph.materials.clearRetainingCapacity();
        self.material_map.clearRetainingCapacity();

        var mesh_desc = MeshDescriptor{};

        mesh_desc.indices = try alloc.alloc(u32, num_indices);
        mesh_desc.positions = try alloc.alloc(f32, 3 * num_vertices);
        mesh_desc.normals = try alloc.alloc(f32, 3 * num_vertices);

        if (has_tangents) {
            mesh_desc.tangents = try alloc.alloc(f32, 4 * num_vertices);
        }

        if (has_uvs) {
            mesh_desc.uvs = try alloc.alloc(f32, 2 * num_vertices);
        }

        var parts = try List(Part).initCapacity(alloc, prim_node.array.items.len);

        var cur_index: u32 = 0;
        var cur_pos: u32 = 0;
        var cur_norm: u32 = 0;
        var cur_tan: u32 = 0;
        var cur_uv: u32 = 0;

        for (prim_node.array.items) |p| {
            const index_id = json.readUIntMember(p, "indices", Null);

            if (Null == index_id) {
                return Error.IndexNoBuffer;
            }

            const attributes = p.object.get("attributes").?;

            const position_id = json.readUIntMember(attributes, "POSITION", Null);
            const normal_id = json.readUIntMember(attributes, "NORMAL", Null);
            const tangent_id = json.readUIntMember(attributes, "TANGENT", Null);
            const uv_id = json.readUIntMember(attributes, "TEXCOORD_0", Null);

            const num_part_indices = try self.loadIndices(alloc, index_id, mesh_desc.indices[cur_index..], cur_pos);

            parts.appendAssumeCapacity(.{
                .start_index = cur_index,
                .num_indices = num_part_indices,
                .material_index = try self.mappedMaterialIndex(alloc, json.readUIntMember(p, "material", Null), graph),
            });

            cur_index += num_part_indices;

            // positions
            {
                const elements = 3;

                const pos_begin = cur_pos * elements;
                cur_pos += try self.loadVertexAttributes(alloc, position_id, mesh_desc.positions[pos_begin..], elements);
            }

            // normals
            {
                const elements = 3;

                const norm_begin = cur_norm * elements;
                cur_norm += try self.loadVertexAttributes(alloc, normal_id, mesh_desc.normals[norm_begin..], elements);
            }

            if (Null != tangent_id) {
                const elements = 4;

                const tan_begin = cur_tan * elements;
                cur_tan += try self.loadVertexAttributes(alloc, tangent_id, mesh_desc.tangents.?[tan_begin..], elements);
            }

            if (Null != uv_id) {
                const elements = 2;

                const uv_begin = cur_uv * elements;
                cur_uv += try self.loadVertexAttributes(alloc, uv_id, mesh_desc.uvs.?[uv_begin..], elements);
            }
        }

        const num_triangles = num_indices / 3;

        var i: u32 = 0;
        while (i < num_triangles) : (i += 1) {
            const b = mesh_desc.indices[i * 3 + 1];
            const c = mesh_desc.indices[i * 3 + 2];

            mesh_desc.indices[i * 3 + 1] = c;
            mesh_desc.indices[i * 3 + 2] = b;
        }

        i = 0;
        while (i < num_vertices) : (i += 1) {
            const z = mesh_desc.positions[i * 3 + 2];
            mesh_desc.positions[i * 3 + 2] = -z;
        }

        i = 0;
        while (i < num_vertices) : (i += 1) {
            const z = mesh_desc.normals[i * 3 + 2];
            mesh_desc.normals[i * 3 + 2] = -z;
        }

        if (mesh_desc.tangents) |tangents| {
            i = 0;
            while (i < num_vertices) : (i += 1) {
                const z = tangents[i * 4 + 2];
                tangents[i * 4 + 2] = -z;

                const w = tangents[i * 4 + 3];
                tangents[i * 4 + 3] = -w;
            }
        }

        const desc = resource.ShapeProvider.Descriptor{
            .num_parts = @intCast(parts.items.len),
            .num_primitives = num_triangles,
            .num_vertices = num_vertices,
            .positions_stride = 3,
            .normals_stride = 3,
            .tangents_stride = if (has_tangents) 4 else 0,
            .uvs_stride = if (has_uvs) 2 else 0,
            .parts = std.mem.bytesAsSlice(u32, std.mem.sliceAsBytes(parts.items)).ptr,
            .indices = mesh_desc.indices.ptr,
            .positions = mesh_desc.positions.ptr,
            .normals = mesh_desc.normals.ptr,
            .tangents = if (mesh_desc.tangents) |t| t.ptr else null,
            .uvs = if (mesh_desc.uvs) |u| u.ptr else null,
        };

        const shape_id = try self.resources.loadData(scn.Shape, alloc, 0xFFFFFFFF, &desc, .{});

        self.resources.commitAsync();

        return try graph.scene.createProp(alloc, shape_id, graph.materials.items);
    }

    fn loadIndices(self: *Self, alloc: Allocator, id: u32, buffer: []u32, cur_vertex: u32) !u32 {
        const index_acc = self.accessors.items[id];
        const index_view = self.buffer_views.items[index_acc.buffer_view];

        var stream = try self.readStream(alloc, index_view.buffer);

        if (.UInt32 == index_acc.component_type) {
            try stream.seekTo(index_acc.byte_offset + index_view.byte_offset);
            _ = try stream.read(std.mem.sliceAsBytes(buffer[0..index_acc.count]));

            for (buffer[0..index_acc.count]) |*o| {
                o.* += cur_vertex;
            }

            return index_acc.count;
        } else if (.UInt16 == index_acc.component_type) {
            const indices_in = try alloc.alloc(u16, index_acc.count);
            defer alloc.free(indices_in);

            try stream.seekTo(index_acc.byte_offset + index_view.byte_offset);
            _ = try stream.read(std.mem.sliceAsBytes(indices_in));

            for (indices_in, buffer[0..index_acc.count]) |i, *o| {
                o.* = i + cur_vertex;
            }

            return index_acc.count;
        } else {
            return Error.IndexInvalidComponentType;
        }
    }

    fn loadVertexAttributes(self: *Self, alloc: Allocator, id: u32, buffer: []f32, comptime Elements: comptime_int) !u32 {
        const vertex_acc = self.accessors.items[id];
        const vertex_view = self.buffer_views.items[vertex_acc.buffer_view];

        const stream = try self.readStream(alloc, vertex_view.buffer);

        const data_begin = vertex_acc.byte_offset + vertex_view.byte_offset;

        if (vertex_view.byte_stride > 4 * Elements) {
            for (0..vertex_acc.count) |i| {
                try stream.seekTo(data_begin + i * vertex_view.byte_stride);

                const begin = i * Elements;
                _ = try stream.read(std.mem.sliceAsBytes(buffer[begin .. begin + Elements]));
            }
        } else {
            try stream.seekTo(data_begin);

            const vertex_end = vertex_acc.count * Elements;
            _ = try stream.read(std.mem.sliceAsBytes(buffer[0..vertex_end]));
        }

        return vertex_acc.count;
    }

    const TextureDescriptor = struct {
        uri: []const u8 = "",

        scale: Vec2f = .{ 1.0, 1.0 },
    };

    fn loadTextureDescriptor(value: std.json.Value, root: std.json.Value) ?TextureDescriptor {
        const tex_id = json.readUIntMember(value, "index", Null);
        if (Null != tex_id) {
            if (root.object.get("textures")) |tex_node| {
                var desc = TextureDescriptor{};

                const img_id = json.readUIntMember(tex_node.array.items[tex_id], "source", Null);
                if (root.object.get("images")) |img_node| {
                    desc.uri = json.readStringMember(img_node.array.items[img_id], "uri", "");
                }

                if (value.object.get("extensions")) |extensions_node| {
                    var iter = extensions_node.object.iterator();
                    while (iter.next()) |entry| {
                        if (std.mem.eql(u8, "KHR_texture_transform", entry.key_ptr.*)) {
                            desc.scale = json.readVec2fMember(entry.value_ptr.*, "scale", desc.scale);
                        }
                    }
                }

                return desc;
            }
        }

        return null;
    }

    const Clearcoat = struct {
        color: Vec4f = @splat(1.0),
        roughness: f32 = 0.0,
        intensity_texture: ?TextureDescriptor = null,
    };

    fn loadMaterial(
        self: *Self,
        alloc: Allocator,
        value: std.json.Value,
        root: std.json.Value,
        global_scale: f32,
    ) !u32 {
        var ior: f32 = 1.5;
        var attenuation_distance: f32 = 0.0;
        var attenuation_color: Vec4f = @splat(0.0);
        var volume = false;

        var clearcoat: ?Clearcoat = null;

        if (value.object.get("extensions")) |extensions_node| {
            var iter = extensions_node.object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "KHR_materials_ior", entry.key_ptr.*)) {
                    ior = json.readFloatMember(entry.value_ptr.*, "ior", ior);
                } else if (std.mem.eql(u8, "KHR_materials_transmission", entry.key_ptr.*)) {
                    // transmission_factor = json.readFloatMember(entry.value_ptr.*, "transmissionFactor", transmission_factor);
                    attenuation_distance = 1.0;
                } else if (std.mem.eql(u8, "KHR_materials_volume", entry.key_ptr.*)) {
                    volume = true;
                    attenuation_color = json.readVec4f3Member(entry.value_ptr.*, "attenuationColor", attenuation_color);
                    attenuation_distance = json.readFloatMember(entry.value_ptr.*, "attenuationDistance", attenuation_distance);
                } else if (std.mem.eql(u8, "KHR_materials_clearcoat", entry.key_ptr.*)) {
                    var coat: Clearcoat = .{};

                    if (entry.value_ptr.object.get("clearcoatTexture")) |coat_tex| {
                        coat.intensity_texture = loadTextureDescriptor(coat_tex, root);
                    }

                    coat.roughness = json.readFloatMember(entry.value_ptr.*, "roughnessFactor", coat.roughness);

                    clearcoat = coat;
                }
            }
        }

        if (value.object.get("pbrMetallicRoughness")) |pbr_node| {
            var buffer: [1024]u8 = undefined;

            var fixed_buffer_stream = std.io.fixedBufferStream(&buffer);
            const stream = fixed_buffer_stream.writer();
            var jw = std.json.writeStream(stream, .{});
            defer jw.deinit();

            try jw.beginObject();
            try jw.objectField("rendering");

            try jw.beginObject();
            try jw.objectField("Substitute");
            try jw.beginObject();

            try jw.objectField("color");

            if (pbr_node.object.get("baseColorTexture")) |base_color_tex| {
                if (loadTextureDescriptor(base_color_tex, root)) |desc| {
                    try jw.beginObject();
                    try jw.objectField("file");
                    try jw.write(desc.uri);
                    try jw.objectField("scale");
                    try jw.write(desc.scale);
                    try jw.endObject();
                }
            } else {
                const color = json.readVec4f3Member(pbr_node, "baseColorFactor", @splat(0.7));

                try jw.beginArray();
                try jw.write(color[0]);
                try jw.write(color[1]);
                try jw.write(color[2]);
                try jw.endArray();
            }

            if (value.object.get("normalTexture")) |normal_tex| {
                if (loadTextureDescriptor(normal_tex, root)) |desc| {
                    try jw.objectField("normal");
                    try jw.beginObject();
                    try jw.objectField("file");
                    try jw.write(desc.uri);
                    try jw.objectField("scale");
                    try jw.write(desc.scale);
                    try jw.endObject();
                }
            }

            if (pbr_node.object.get("metallicRoughnessTexture")) |mr_tex| {
                if (loadTextureDescriptor(mr_tex, root)) |desc| {
                    try jw.objectField("surface");
                    try jw.beginObject();
                    try jw.objectField("file");
                    try jw.write(desc.uri);
                    try jw.objectField("swizzle");
                    try jw.write("YZ");
                    try jw.objectField("scale");
                    try jw.write(desc.scale);
                    try jw.endObject();
                }
            } else {
                const roughness = json.readFloatMember(pbr_node, "roughnessFactor", 0.7);

                const metallic = json.readFloatMember(pbr_node, "metallicFactor", 1.0);

                try jw.objectField("roughness");
                try jw.write(roughness);
                try jw.objectField("metallic");
                try jw.write(metallic);
            }

            if (value.object.get("emissiveTexture")) |emissive_tex| {
                if (loadTextureDescriptor(emissive_tex, root)) |desc| {
                    try jw.objectField("emission");
                    try jw.beginObject();
                    try jw.objectField("file");
                    try jw.write(desc.uri);
                    try jw.objectField("scale");
                    try jw.write(desc.scale);
                    try jw.endObject();
                }
            }

            const emissive_factor = json.readVec4f3Member(value, "emissiveFactor", @splat(0.0));
            if (math.anyGreaterZero3(emissive_factor)) {
                try jw.objectField("emittance");
                try jw.beginObject();
                try jw.objectField("spectrum");
                try jw.beginArray();
                try jw.write(emissive_factor[0]);
                try jw.write(emissive_factor[1]);
                try jw.write(emissive_factor[2]);
                try jw.endArray();
                try jw.endObject();
            }

            try jw.objectField("ior");
            try jw.write(ior);

            if (volume) {
                try jw.objectField("attenuation_color");
                try jw.beginArray();
                try jw.write(attenuation_color[0]);
                try jw.write(attenuation_color[1]);
                try jw.write(attenuation_color[2]);
                try jw.endArray();
            }

            if (attenuation_distance > 0.0) {
                try jw.objectField("attenuation_distance");
                try jw.write(global_scale * attenuation_distance);
            }

            if (clearcoat) |coat| {
                try jw.objectField("coating");
                try jw.beginObject();
                try jw.objectField("ior");
                try jw.write(1.5);
                try jw.objectField("roughness");
                try jw.write(coat.roughness);

                if (coat.intensity_texture) |tex| {
                    try jw.objectField("thickness");
                    try jw.beginObject();
                    try jw.objectField("file");
                    try jw.write(tex.uri);
                    try jw.objectField("scale");
                    try jw.write(tex.scale);
                    try jw.objectField("value");
                    try jw.write(0.001);
                    try jw.endObject();
                } else {
                    try jw.objectField("thickness");
                    try jw.write(0.001);
                }

                try jw.endObject();
            }

            try jw.endObject();
            try jw.endObject();
            try jw.endObject();

            fixed_buffer_stream = std.io.fixedBufferStream(fixed_buffer_stream.getWritten());
            var json_reader = std.json.reader(alloc, fixed_buffer_stream.reader());
            defer json_reader.deinit();

            var parsed = try std.json.parseFromTokenSource(std.json.Value, alloc, &json_reader, .{});
            defer parsed.deinit();

            return try self.resources.loadData(scn.Material, alloc, 0xFFFFFFFF, &parsed.value, .{});
        }

        return Null;
    }
};
