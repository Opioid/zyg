const gltf = @import("gltf_loader.zig");
const Graph = @import("scene_graph.zig").Graph;

const core = @import("core");
const log = core.log;
const scn = core.scn;
const Scene = scn.Scene;
const Prop = scn.Prop;
const Material = scn.Material;
const Shape = scn.Shape;
const Instancer = scn.Instancer;
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
        UndefinedType,
        UndefinedShape,
    } || Allocator.Error;

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

        const parent_trafo: Transformation = .identity;

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
        for (value.array.items) |entity_value| {
            if (entity_value.object.get("file")) |file_node| {
                const filename = file_node.string;
                self.loadFile(alloc, filename, "", parent_id, parent_trafo, animated, graph) catch |e| {
                    log.err("Loading scene \"{s}\": {}", .{ filename, e });
                };
                continue;
            }

            const leaf = self.loadLeafEntity(
                alloc,
                entity_value,
                parent_id,
                parent_trafo,
                animated,
                local_materials,
                graph,
                false,
            ) catch continue;

            if (leaf.children_ptr) |children| {
                try self.loadEntities(
                    alloc,
                    children.*,
                    leaf.graph.graph_id,
                    leaf.graph.world_trafo,
                    leaf.graph.animated,
                    local_materials,
                    graph,
                );
            }

            if (leaf.is_scatterer) {
                try self.loadScatterer(
                    alloc,
                    entity_value,
                    leaf.graph.graph_id,
                    leaf.graph.world_trafo,
                    leaf.graph.animated,
                    local_materials,
                    graph,
                );
            }
        }
    }

    const Leaf = struct {
        entity_id: u32,
        graph: Graph.TrafoResult,
        children_ptr: ?*std.json.Value,
        is_scatterer: bool,
    };

    fn loadLeafEntity(
        self: *Loader,
        alloc: Allocator,
        value: std.json.Value,
        parent_id: u32,
        parent_trafo: Transformation,
        animated: bool,
        local_materials: LocalMaterials,
        graph: *Graph,
        prototype: bool,
    ) !Leaf {
        const type_node = value.object.get("type") orelse return Error.UndefinedType;
        const type_name = type_node.string;

        var entity_id: u32 = Prop.Null;
        var is_light = false;
        var is_scatterer = false;

        if (std.mem.eql(u8, "Light", type_name)) {
            entity_id = try self.loadProp(alloc, value, local_materials, graph, false, true, prototype);
            is_light = true;
        } else if (std.mem.eql(u8, "Prop", type_name)) {
            entity_id = try self.loadProp(alloc, value, local_materials, graph, true, false, prototype);
        } else if (std.mem.eql(u8, "Instancer", type_name)) {
            entity_id = try self.loadInstancer(alloc, value, parent_id, parent_trafo, local_materials, graph, prototype);
        } else if (std.mem.eql(u8, "Sky", type_name)) {
            entity_id = try loadSky(alloc, value, graph);
        } else if (std.mem.eql(u8, "Scatterer", type_name)) {
            is_scatterer = true;
        }

        var trafo: Transformation = .identity;

        var animation_ptr: ?*std.json.Value = null;
        var children_ptr: ?*std.json.Value = null;
        var visibility_ptr: ?*std.json.Value = null;
        var shadow_catcher_ptr: ?*std.json.Value = null;

        var iter = value.object.iterator();
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

        const scene = &graph.scene;

        if (Prop.Null != entity_id) {
            const prop = scene.prop(entity_id);

            if (prop.volume() and !prop.instancer() and trafo.scale[1] <= 0.0 and trafo.scale[2] <= 2.0) {
                const material = scene.propMaterial(entity_id, 0);
                if (material.heterogeneousVolume()) {
                    if (material.usefulTexture()) |t| {
                        const voxel_scale: Vec4f = @splat(trafo.scale[0]);
                        const dimensions = t.dimensions(scene);
                        var offset: Vec4i = @splat(0);

                        if (self.resources.images.meta(t.data.image.id)) |meta| {
                            offset = meta.queryOr("offset", offset);

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

                        trafo.scale = voxel_scale * @as(Vec4f, @floatFromInt(dimensions));
                        trafo.position += (@as(Vec4f, @splat(0.5)) * trafo.scale) + voxel_scale * @as(Vec4f, @floatFromInt(offset));
                    }
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

        return Leaf{
            .entity_id = entity_id,
            .graph = graph_trafo,
            .children_ptr = children_ptr,
            .is_scatterer = is_scatterer,
        };
    }

    fn loadProp(
        self: *Loader,
        alloc: Allocator,
        value: std.json.Value,
        local_materials: LocalMaterials,
        graph: *Graph,
        instancing: bool,
        unoccluding_default: bool,
        prototype: bool,
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

        if (instancing and !prototype) {
            const key = Key{ .shape = shape, .materials = graph.materials.items };

            if (self.instances.get(key)) |instance| {
                return try scene.createPropInstance(alloc, instance);
            }

            const entity = try scene.createPropShape(alloc, shape, graph.materials.items, false, prototype);
            try self.instances.put(alloc, try key.clone(alloc), entity);
            return entity;
        } else {
            const unoccluding = !json.readBoolMember(value, "occluding", !unoccluding_default);
            return try scene.createPropShape(alloc, shape, graph.materials.items, unoccluding, prototype);
        }
    }

    fn loadInstancer(
        self: *Loader,
        alloc: Allocator,
        value: std.json.Value,
        parent_id: u32,
        parent_trafo: Transformation,
        local_materials: LocalMaterials,
        graph: *Graph,
        prototype: bool,
    ) Error!u32 {
        if (value.object.get("source")) |file_node| {
            const filename = file_node.string;
            return self.loadInstancerFile(alloc, filename, parent_id, parent_trafo, graph, prototype) catch |e| {
                log.err("Loading instancer file \"{s}\": {}", .{ filename, e });
                return Scene.Null;
            };
        }

        var prototypes: List(u32) = .empty;
        defer prototypes.deinit(alloc);

        var instances_ptr: ?*std.json.Value = null;

        {
            var iter = value.object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "prototypes", entry.key_ptr.*)) {
                    const proto_array = entry.value_ptr.array;
                    prototypes = try List(u32).initCapacity(alloc, proto_array.items.len);

                    for (proto_array.items) |proto_value| {
                        const proto = self.loadLeafEntity(
                            alloc,
                            proto_value,
                            parent_id,
                            parent_trafo,
                            false,
                            local_materials,
                            graph,
                            true,
                        ) catch
                            continue;

                        prototypes.appendAssumeCapacity(proto.entity_id);
                    }
                } else if (std.mem.eql(u8, "instances", entry.key_ptr.*)) {
                    instances_ptr = entry.value_ptr;
                }
            }
        }

        if (instances_ptr) |instances_value| {
            const proto_indices_value = instances_value.object.get("prototypes") orelse {
                log.err("Scatterer: No protype indices", .{});
                return Scene.Null;
            };

            const trafos_value = instances_value.object.get("transformations") orelse {
                log.err("Scatterer: No protype transformations", .{});
                return Scene.Null;
            };

            var instancer = try Instancer.init(alloc, @truncate(proto_indices_value.array.items.len));

            var solids: List(u32) = .{};
            var volumes: List(u32) = .{};

            defer {
                volumes.deinit(alloc);
                solids.deinit(alloc);
            }

            for (proto_indices_value.array.items, trafos_value.array.items, 0..) |proto_index_value, trafo_value, i| {
                var proto_index = json.readUInt(proto_index_value);
                if (proto_index >= prototypes.items.len) {
                    proto_index = 0;
                }

                var trafo: Transformation = .identity;

                json.readTransformation(trafo_value, &trafo);

                const proto_entity_id = prototypes.items[proto_index];

                try instancer.allocateInstance(alloc, proto_entity_id);

                const instance_id: u32 = @truncate(i);

                instancer.space.setWorldTransformation(instance_id, trafo);

                const po = graph.scene.prop(proto_entity_id);

                if (po.solid()) {
                    try solids.append(alloc, instance_id);
                }

                if (po.volume()) {
                    try volumes.append(alloc, instance_id);
                }
            }

            self.resources.commitAsync();

            instancer.calculateWorldBounds(&graph.scene);

            try graph.scene.bvh_builder.build(
                alloc,
                &instancer.solid_bvh,
                solids.items,
                instancer.space.aabbs.items,
                self.resources.threads,
            );

            try graph.scene.bvh_builder.build(
                alloc,
                &instancer.volume_bvh,
                volumes.items,
                instancer.space.aabbs.items,
                self.resources.threads,
            );

            const shape = try self.resources.instancers.store(alloc, Scene.Null, instancer);

            return try graph.scene.createPropInstancer(alloc, shape, prototype);
        }

        return Scene.Null;
    }

    fn loadInstancerFile(
        self: *Loader,
        alloc: Allocator,
        filename: []const u8,
        parent_id: u32,
        parent_trafo: Transformation,
        graph: *Graph,
        prototype: bool,
    ) !u32 {
        if (self.resources.instancers.getByName(filename, .{})) |shape_id| {
            return try graph.scene.createPropInstancer(alloc, shape_id, prototype);
        }

        const fs = &self.resources.fs;

        var stream = try fs.readStream(alloc, filename);

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

        var local_materials = LocalMaterials.init(alloc);
        defer local_materials.deinit();

        if (root.object.get("materials")) |materials_node| {
            try readMaterials(materials_node, &local_materials);
        }

        const entity_id = try self.loadInstancer(alloc, root, parent_id, parent_trafo, local_materials, graph, prototype);

        if (Scene.Null != entity_id) {
            const shape_id = graph.scene.prop(entity_id).resource;
            try self.resources.instancers.associate(alloc, shape_id, filename, .{});
        }

        return entity_id;
    }

    fn loadScatterer(
        self: *Loader,
        alloc: Allocator,
        value: std.json.Value,
        parent_id: u32,
        parent_trafo: Transformation,
        animated: bool,
        local_materials: LocalMaterials,
        graph: *Graph,
    ) !void {
        var prototypes: List(u32) = .empty;
        defer prototypes.deinit(alloc);

        var instances_ptr: ?*std.json.Value = null;

        {
            var iter = value.object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "prototypes", entry.key_ptr.*)) {
                    const proto_array = entry.value_ptr.array;
                    prototypes = try List(u32).initCapacity(alloc, proto_array.items.len);

                    for (proto_array.items) |proto_value| {
                        const proto = self.loadLeafEntity(
                            alloc,
                            proto_value,
                            parent_id,
                            parent_trafo,
                            animated,
                            local_materials,
                            graph,
                            true,
                        ) catch
                            continue;

                        prototypes.appendAssumeCapacity(proto.entity_id);
                    }
                } else if (std.mem.eql(u8, "instances", entry.key_ptr.*)) {
                    instances_ptr = entry.value_ptr;
                }
            }
        }

        if (instances_ptr) |instances_value| {
            const scene = &graph.scene;

            const proto_indices_value = instances_value.object.get("prototypes") orelse {
                log.err("Scatterer: No protype indices", .{});
                return;
            };

            const trafos_value = instances_value.object.get("transformations") orelse {
                log.err("Scatterer: No protype transformations", .{});
                return;
            };

            for (proto_indices_value.array.items, trafos_value.array.items) |proto_index_value, trafo_value| {
                var proto_index = json.readUInt(proto_index_value);
                if (proto_index >= prototypes.items.len) {
                    proto_index = 0;
                }

                var trafo: Transformation = .identity;

                json.readTransformation(trafo_value, &trafo);

                const proto_entity_id = prototypes.items[proto_index];

                const entity_id = try scene.createPropInstance(alloc, proto_entity_id);

                _ = try graph.propSetTransformation(
                    alloc,
                    entity_id,
                    parent_id,
                    trafo,
                    parent_trafo,
                    null,
                    animated,
                );
            }
        }
    }

    fn setVisibility(prop: u32, value: std.json.Value, scene: *Scene) void {
        var in_camera = true;
        var in_reflection = true;
        var shadow_catcher_light = false;

        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "in_camera", entry.key_ptr.*)) {
                in_camera = json.readBool(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "in_reflection", entry.key_ptr.*)) {
                in_reflection = json.readBool(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "shadow_catcher_light", entry.key_ptr.*)) {
                shadow_catcher_light = json.readBool(entry.value_ptr.*);
            }
        }

        scene.propSetVisibility(prop, in_camera, in_reflection, shadow_catcher_light);
    }

    fn setShadowCatcher(prop: u32, value: std.json.Value, scene: *Scene) void {
        _ = value;

        scene.propSetShadowCatcher(prop);
    }

    fn loadShape(self: *const Loader, alloc: Allocator, value: std.json.Value) !u32 {
        const type_name = json.readStringMember(value, "type", "");
        if (type_name.len > 0) {
            return getShape(type_name);
        }

        const file = json.readStringMember(value, "file", "");
        if (file.len > 0) {
            return self.resources.loadFile(Shape, alloc, file, .{});
        }

        return Error.UndefinedShape;
    }

    pub fn getShape(type_name: []const u8) !u32 {
        if (std.mem.eql(u8, "Canopy", type_name)) {
            return @intFromEnum(Scene.ShapeID.Canopy);
        } else if (std.mem.eql(u8, "Cube", type_name)) {
            return @intFromEnum(Scene.ShapeID.Cube);
        } else if (std.mem.eql(u8, "Disk", type_name)) {
            return @intFromEnum(Scene.ShapeID.Disk);
        } else if (std.mem.eql(u8, "DistantSphere", type_name)) {
            return @intFromEnum(Scene.ShapeID.DistantSphere);
        } else if (std.mem.eql(u8, "InfiniteSphere", type_name)) {
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
