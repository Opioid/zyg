const gltf = @import("gltf_loader.zig");
const Graph = @import("scene_graph.zig").Graph;

const core = @import("core");
const log = core.log;
const img = core.img;
const scn = core.scn;
const Scene = scn.Scene;
const Prop = scn.Prop;
const Material = scn.Material;
const Shape = scn.Shape;
const resource = core.resource;
const Resources = resource.Manager;
const Take = core.tk.Take;

const base = @import("base");
const json = base.json;
const string = base.string;
const math = base.math;
const Vec4f = math.Vec4f;
const Vec4i = math.Vec4i;
const Transformation = math.Transformation;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

const Key = struct {
    shape: u32,
    materials: []u32 = &.{},

    const Self = @This();

    pub fn clone(self: Self, alloc: Allocator) !Self {
        return Self{
            .shape = self.shape,
            .materials = try alloc.dupe(u32, self.materials),
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.materials);
    }
};

const KeyContext = struct {
    const Self = @This();

    pub fn hash(self: Self, k: Key) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);

        hasher.update(std.mem.asBytes(&k.shape));

        for (k.materials) |m| {
            hasher.update(std.mem.asBytes(&m));
        }

        return hasher.final();
    }

    pub fn eql(self: Self, a: Key, b: Key) bool {
        _ = self;

        if (a.shape != b.shape) {
            return false;
        }

        if (a.materials.len != b.materials.len) {
            return false;
        }

        for (a.materials, 0..) |m, i| {
            if (m != b.materials[i]) {
                return false;
            }
        }

        return true;
    }
};

pub const Loader = struct {
    const Error = error{
        OutOfMemory,
        UndefinedShape,
    };

    resources: *Resources,

    fallback_material: u32,

    instances: std.HashMapUnmanaged(Key, u32, KeyContext, 80) = .{},

    const Null = resource.Null;

    const LocalMaterials = struct {
        materials: std.StringHashMap(*std.json.Value),

        pub fn init(alloc: Allocator) LocalMaterials {
            return .{ .materials = std.StringHashMap(*std.json.Value).init(alloc) };
        }

        pub fn deinit(self: *LocalMaterials) void {
            self.materials.deinit();
        }
    };

    pub fn init(alloc: Allocator, resources: *Resources, fallback_material: Material) Loader {
        return .{
            .resources = resources,
            .fallback_material = resources.materials.store(alloc, Null, fallback_material) catch Null,
        };
    }

    pub fn deinit(self: *Loader, alloc: Allocator) void {
        self.instances.deinit(alloc);
    }

    pub fn load(self: *Loader, alloc: Allocator, graph: *Graph) !void {
        const take_mount_folder = string.parentDirectory(graph.take.resolved_filename);

        const parent_id: u32 = Prop.Null;

        const parent_trafo = Transformation{
            .position = @splat(0.0),
            .scale = @splat(1.0),
            .rotation = math.quaternion.identity,
        };

        try self.loadFile(alloc, graph.take.scene_filename, take_mount_folder, parent_id, parent_trafo, false, graph);

        var iter = self.instances.keyIterator();
        while (iter.next()) |k| {
            k.deinit(alloc);
        }

        self.instances.clearAndFree(alloc);

        self.resources.commitAsync();
    }

    fn loadFile(
        self: *Loader,
        alloc: Allocator,
        filename: []const u8,
        take_mount_folder: []const u8,
        parent_id: u32,
        parent_trafo: Transformation,
        animated: bool,
        graph: *Graph,
    ) !void {
        const fs = &self.resources.fs;

        if (take_mount_folder.len > 0) {
            try fs.pushMount(alloc, take_mount_folder);
        }

        var stream = try fs.readStream(alloc, filename);

        if (take_mount_folder.len > 0) {
            fs.popMount(alloc);
        }

        const buffer = try stream.readAll(alloc);
        stream.deinit();
        defer alloc.free(buffer);

        var parsed = try std.json.parseFromSlice(
            std.json.Value,
            alloc,
            buffer,
            .{ .duplicate_field_behavior = .use_last },
        );
        defer parsed.deinit();

        const root = parsed.value;

        try fs.pushMount(alloc, string.parentDirectory(fs.lastResolvedName()));
        defer fs.popMount(alloc);

        var gltf_loader = gltf.Loader.init(self.resources, self.fallback_material);
        if (try gltf_loader.load(alloc, root, parent_trafo, graph)) {
            gltf_loader.deinit(alloc);
            return;
        }

        var local_materials = LocalMaterials.init(alloc);
        defer local_materials.deinit();

        if (root.object.get("materials")) |materials_node| {
            try readMaterials(materials_node, &local_materials);
        }

        var iter = root.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "entities", entry.key_ptr.*)) {
                try self.loadEntities(
                    alloc,
                    entry.value_ptr.*,
                    parent_id,
                    parent_trafo,
                    animated,
                    local_materials,
                    graph,
                );
            }
        }
    }

    fn readMaterials(value: std.json.Value, local_materials: *LocalMaterials) !void {
        for (value.array.items) |*m| {
            const name_node = m.object.get("name") orelse continue;

            try local_materials.materials.put(name_node.string, m);
        }
    }

    fn loadEntities(
        self: *Loader,
        alloc: Allocator,
        value: std.json.Value,
        parent_id: u32,
        parent_trafo: Transformation,
        animated: bool,
        local_materials: LocalMaterials,
        graph: *Graph,
    ) Error!void {
        const scene = &graph.scene;

        for (value.array.items) |entity| {
            if (entity.object.get("file")) |file_node| {
                const filename = file_node.string;
                self.loadFile(alloc, filename, "", parent_id, parent_trafo, animated, graph) catch |e| {
                    log.err("Loading scene \"{s}\": {}", .{ filename, e });
                };
                continue;
            }

            const type_node = entity.object.get("type") orelse continue;
            const type_name = type_node.string;

            var entity_id: u32 = Prop.Null;
            var is_light = false;

            if (std.mem.eql(u8, "Light", type_name)) {
                entity_id = self.loadProp(alloc, entity, local_materials, graph, false) catch continue;
                is_light = true;
            } else if (std.mem.eql(u8, "Prop", type_name)) {
                entity_id = self.loadProp(alloc, entity, local_materials, graph, true) catch continue;
            } else if (std.mem.eql(u8, "Sky", type_name)) {
                entity_id = loadSky(alloc, entity, graph) catch continue;
            }

            var trafo = Transformation{
                .position = @splat(0.0),
                .scale = @splat(1.0),
                .rotation = math.quaternion.identity,
            };

            var animation_ptr: ?*std.json.Value = null;
            var children_ptr: ?*std.json.Value = null;
            var visibility_ptr: ?*std.json.Value = null;
            var shadow_catcher_ptr: ?*std.json.Value = null;

            var iter = entity.object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "transformation", entry.key_ptr.*)) {
                    json.readTransformation(entry.value_ptr.*, &trafo);
                } else if (std.mem.eql(u8, "animation", entry.key_ptr.*)) {
                    animation_ptr = entry.value_ptr;
                } else if (std.mem.eql(u8, "entities", entry.key_ptr.*)) {
                    children_ptr = entry.value_ptr;
                } else if (std.mem.eql(u8, "visibility", entry.key_ptr.*)) {
                    visibility_ptr = entry.value_ptr;
                } else if (std.mem.eql(u8, "shadow_catcher", entry.key_ptr.*)) {
                    shadow_catcher_ptr = entry.value_ptr;
                }
            }

            if (trafo.scale[1] <= 0.0 and trafo.scale[2] <= 2 and 1 == scene.propShape(entity_id).numParts()) {
                const material = scene.propMaterial(entity_id, 0);
                if (material.heterogeneousVolume()) {
                    if (material.usefulTexture()) |t| {
                        const voxel_scale: Vec4f = @splat(trafo.scale[0]);
                        const dimensions = t.description(scene).dimensions;
                        var offset: Vec4i = @splat(0);

                        if (self.resources.images.meta(t.image)) |meta| {
                            offset = meta.queryOrDef("offset", offset);

                            // HACK, where do those values come from?!?!
                            if (offset[0] == 0x7FFFFFFF) {
                                offset[0] = 0;
                            }

                            if (offset[1] == 0x7FFFFFFF) {
                                offset[1] = 0;
                            }

                            if (offset[2] == 0x7FFFFFFF) {
                                offset[2] = 0;
                            }
                        }

                        trafo.scale = @as(Vec4f, @splat(0.5)) * voxel_scale * @as(Vec4f, @floatFromInt(dimensions));
                        trafo.position += trafo.scale + voxel_scale * @as(Vec4f, @floatFromInt(offset));
                    }
                }
            }

            const graph_trafo = try graph.propSetTransformation(
                alloc,
                entity_id,
                parent_id,
                trafo,
                parent_trafo,
                animation_ptr,
                animated,
            );

            if (visibility_ptr) |visibility| {
                setVisibility(entity_id, visibility.*, scene);
            }

            if (shadow_catcher_ptr) |shadow_catcher| {
                setShadowCatcher(entity_id, shadow_catcher.*, scene);
            }

            if (is_light and scene.prop(entity_id).visibleInReflection()) {
                try scene.createLight(alloc, entity_id);
            }

            if (children_ptr) |children| {
                try self.loadEntities(
                    alloc,
                    children.*,
                    graph_trafo.graph_id,
                    graph_trafo.world_trafo,
                    graph_trafo.animated,
                    local_materials,
                    graph,
                );
            }
        }
    }

    fn loadProp(
        self: *Loader,
        alloc: Allocator,
        value: std.json.Value,
        local_materials: LocalMaterials,
        graph: *Graph,
        instancing: bool,
    ) !u32 {
        const shape = if (value.object.get("shape")) |s| try self.loadShape(alloc, s) else return Error.UndefinedShape;

        const scene = &graph.scene;
        const num_materials = scene.shape(shape).numMaterials();

        try graph.materials.ensureTotalCapacity(alloc, num_materials);
        graph.materials.clearRetainingCapacity();

        if (value.object.get("materials")) |m| {
            self.loadMaterials(alloc, m, &graph.materials, num_materials, local_materials);
        }

        while (graph.materials.items.len < num_materials) {
            graph.materials.appendAssumeCapacity(self.fallback_material);
        }

        if (instancing) {
            const key = Key{ .shape = shape, .materials = graph.materials.items };

            if (self.instances.get(key)) |instance| {
                return try scene.createPropInstance(alloc, instance);
            }

            const entity = try scene.createProp(alloc, shape, graph.materials.items);
            try self.instances.put(alloc, try key.clone(alloc), entity);
            return entity;
        } else {
            return try scene.createProp(alloc, shape, graph.materials.items);
        }
    }

    fn setVisibility(prop: u32, value: std.json.Value, scene: *Scene) void {
        var in_camera = true;
        var in_reflection = true;
        var in_shadow = true;
        var shadow_catcher_light = false;

        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "in_camera", entry.key_ptr.*)) {
                in_camera = json.readBool(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "in_reflection", entry.key_ptr.*)) {
                in_reflection = json.readBool(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "in_shadow", entry.key_ptr.*)) {
                in_shadow = json.readBool(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "shadow_catcher_light", entry.key_ptr.*)) {
                shadow_catcher_light = json.readBool(entry.value_ptr.*);
            }
        }

        scene.propSetVisibility(prop, in_camera, in_reflection, in_shadow, shadow_catcher_light);
    }

    fn setShadowCatcher(prop: u32, value: std.json.Value, scene: *Scene) void {
        _ = value;

        scene.propSetShadowCatcher(prop);
    }

    fn loadShape(self: *const Loader, alloc: Allocator, value: std.json.Value) !u32 {
        const type_name = json.readStringMember(value, "type", "");
        if (type_name.len > 0) {
            return try getShape(type_name);
        }

        const file = json.readStringMember(value, "file", "");
        if (file.len > 0) {
            return self.resources.loadFile(Shape, alloc, file, .{});
        }

        return Error.UndefinedShape;
    }

    fn getShape(type_name: []const u8) !u32 {
        if (std.mem.eql(u8, "Canopy", type_name)) {
            return @intFromEnum(Scene.ShapeID.Canopy);
        } else if (std.mem.eql(u8, "Cube", type_name)) {
            return @intFromEnum(Scene.ShapeID.Cube);
        } else if (std.mem.eql(u8, "Disk", type_name)) {
            return @intFromEnum(Scene.ShapeID.Disk);
        } else if (std.mem.eql(u8, "Distant_sphere", type_name)) {
            return @intFromEnum(Scene.ShapeID.DistantSphere);
        } else if (std.mem.eql(u8, "Infinite_sphere", type_name)) {
            return @intFromEnum(Scene.ShapeID.InfiniteSphere);
        } else if (std.mem.eql(u8, "Rectangle", type_name)) {
            return @intFromEnum(Scene.ShapeID.Rectangle);
        } else if (std.mem.eql(u8, "Sphere", type_name)) {
            return @intFromEnum(Scene.ShapeID.Sphere);
        }

        log.err("Undefined shape \"{s}\"", .{type_name});

        return Error.UndefinedShape;
    }

    fn loadMaterials(
        self: *Loader,
        alloc: Allocator,
        value: std.json.Value,
        materials: *List(u32),
        num_materials: usize,
        local_materials: LocalMaterials,
    ) void {
        for (value.array.items, 0..) |m, i| {
            materials.appendAssumeCapacity(self.loadMaterial(alloc, m.string, local_materials));

            if (i == num_materials - 1) {
                return;
            }
        }
    }

    fn loadMaterial(self: *const Loader, alloc: Allocator, name: []const u8, local_materials: LocalMaterials) u32 {
        // First, check if we maybe already have cached the material.
        if (self.resources.getByName(Material, name, .{})) |material| {
            return material;
        }

        // Otherwise, see if it is among the locally defined materials.
        if (local_materials.materials.get(name)) |material_node| {
            const material = self.resources.loadData(Material, alloc, Null, material_node, .{}) catch Null;
            if (Null != material) {
                self.resources.associate(Material, alloc, material, name, .{}) catch {};
                return material;
            }
        }

        // Lastly, try loading the material from the filesystem.
        const material = self.resources.loadFile(Material, alloc, name, .{}) catch {
            log.warning("Using fallback for material \"{s}\"", .{name});
            return self.fallback_material;
        };

        return material;
    }

    fn loadSky(alloc: Allocator, value: std.json.Value, graph: *Graph) !u32 {
        const sky = try graph.scene.createSky(alloc);

        // try graph.bumpProps(alloc);

        if (value.object.get("parameters")) |parameters| {
            sky.setParameters(parameters);
        }

        return sky.sun;
    }
};
