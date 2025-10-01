const gltf = @import("gltf_loader.zig");
const Graph = @import("scene_graph.zig").Graph;

const core = @import("core");
const log = core.log;
const Scene = core.scene.Scene;
const Prop = core.scene.Prop;
const Material = core.scene.Material;
const Shape = core.scene.Shape;
const Instancer = core.scene.Instancer;
const Resources = core.resource.Manager;

const base = @import("base");
const json = base.json;
const string = base.string;
const math = base.math;
const Vec4f = math.Vec4f;
const Vec4i = math.Vec4i;
const Transformation = math.Transformation;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayList;

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

    const Null = Resources.Null;

    const LocalMaterials = std.StringHashMapUnmanaged(*std.json.Value);

    const Node = struct {
        entity_id: u32,
        graph: Graph.Node,
        children_ptr: ?*std.json.Value,
        is_scatterer: bool,
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

        const parent = Graph.Node.empty;

        try self.loadFile(alloc, graph.take.scene_filename, take_mount_folder, parent, graph);

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
        parent: Graph.Node,
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

        const buffer = try stream.readAlloc(alloc);
        defer alloc.free(buffer);

        stream.deinit();

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
        if (try gltf_loader.load(alloc, root, parent.world_trafo, graph)) {
            gltf_loader.deinit(alloc);
            return;
        }

        var local_materials: LocalMaterials = .{};
        defer local_materials.deinit(alloc);

        if (root.object.get("materials")) |materials_node| {
            try readMaterials(alloc, materials_node, &local_materials);
        }

        if (root.object.get("entities")) |entities_node| {
            try self.loadEntities(
                alloc,
                entities_node,
                parent,
                local_materials,
                graph,
            );
        }
    }

    fn readMaterials(alloc: Allocator, value: std.json.Value, local_materials: *LocalMaterials) !void {
        for (value.array.items) |*m| {
            const name_node = m.object.get("name") orelse continue;

            try local_materials.put(alloc, name_node.string, m);
        }
    }

    fn loadEntities(
        self: *Loader,
        alloc: Allocator,
        value: std.json.Value,
        parent: Graph.Node,
        local_materials: LocalMaterials,
        graph: *Graph,
    ) Error!void {
        for (value.array.items) |entity_value| {
            if (entity_value.object.get("file")) |file_node| {
                const filename = file_node.string;
                self.loadFile(alloc, filename, "", parent, graph) catch |e| {
                    log.err("Loading scene \"{s}\": {}", .{ filename, e });
                };
                continue;
            }

            const node = self.loadEntity(alloc, entity_value, parent, local_materials, graph, false) catch continue;

            if (node.children_ptr) |children| {
                try self.loadEntities(alloc, children.*, node.graph, local_materials, graph);
            }

            if (node.is_scatterer) {
                try self.loadScatterer(alloc, entity_value, node.graph, local_materials, graph);
            }
        }
    }

    fn loadEntity(
        self: *Loader,
        alloc: Allocator,
        value: std.json.Value,
        parent: Graph.Node,
        local_materials: LocalMaterials,
        graph: *Graph,
        prototype: bool,
    ) !Node {
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
            entity_id = try self.loadInstancer(alloc, value, parent, local_materials, graph, prototype);
        } else if (std.mem.eql(u8, "Sky", type_name)) {
            entity_id = try loadSky(alloc, value, graph);
        } else if (std.mem.eql(u8, "Scatterer", type_name)) {
            is_scatterer = true;
        }

        var trafo: Transformation = .identity;
        if (value.object.get("transformation")) |trafo_value| {
            json.readTransformation(trafo_value, &trafo);
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

        const graph_node = try graph.propSetTransformation(alloc, entity_id, trafo, parent, value.object.get("animation"));

        if (value.object.get("visibility")) |visibility| {
            setVisibility(entity_id, visibility, scene);
        }

        if (value.object.get("shadow_catcher")) |shadow_catcher| {
            setShadowCatcher(entity_id, shadow_catcher, scene);
        }

        if (is_light and scene.prop(entity_id).visibleInReflection()) {
            try scene.createLight(alloc, entity_id);
        }

        return Node{
            .entity_id = entity_id,
            .graph = graph_node,
            .children_ptr = value.object.getPtr("entities"),
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
                return scene.createPropInstance(alloc, instance);
            }

            const entity = try scene.createPropShape(alloc, shape, graph.materials.items, false, prototype);
            try self.instances.put(alloc, try key.clone(alloc), entity);
            return entity;
        } else {
            const unoccluding = !json.readBoolMember(value, "occluding", !unoccluding_default);
            return scene.createPropShape(alloc, shape, graph.materials.items, unoccluding, prototype);
        }
    }

    fn loadInstancer(
        self: *Loader,
        alloc: Allocator,
        value: std.json.Value,
        parent: Graph.Node,
        local_materials: LocalMaterials,
        graph: *Graph,
        prototype: bool,
    ) Error!u32 {
        if (value.object.get("source")) |file_node| {
            const filename = file_node.string;
            return self.loadInstancerFile(alloc, filename, parent, graph, prototype) catch |e| {
                log.err("Loading instancer file \"{s}\": {}", .{ filename, e });
                return Scene.Null;
            };
        }

        var prototypes: List(u32) = .empty;
        defer prototypes.deinit(alloc);

        if (value.object.get("prototypes")) |prototypes_node| {
            const proto_array = prototypes_node.array;
            prototypes = try List(u32).initCapacity(alloc, proto_array.items.len);

            for (proto_array.items) |proto_value| {
                const proto = self.loadEntity(alloc, proto_value, parent, local_materials, graph, true) catch continue;

                prototypes.appendAssumeCapacity(proto.entity_id);
            }
        }

        if (value.object.get("instances")) |instances_node| {
            const proto_indices_value = instances_node.object.get("prototypes") orelse {
                log.err("Scatterer: No protype indices", .{});
                return Scene.Null;
            };

            const trafos_value = instances_node.object.get("transformations") orelse {
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

            return graph.scene.createPropInstancer(alloc, shape, prototype);
        }

        return Scene.Null;
    }

    fn loadInstancerFile(
        self: *Loader,
        alloc: Allocator,
        filename: []const u8,
        parent: Graph.Node,
        graph: *Graph,
        prototype: bool,
    ) !u32 {
        if (self.resources.instancers.getByName(filename, .{})) |shape_id| {
            return graph.scene.createPropInstancer(alloc, shape_id, prototype);
        }

        const fs = &self.resources.fs;

        var stream = try fs.readStream(alloc, filename);

        const buffer = try stream.readAlloc(alloc);
        defer alloc.free(buffer);

        stream.deinit();

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

        var local_materials: LocalMaterials = .{};
        defer local_materials.deinit(alloc);

        if (root.object.get("materials")) |materials_node| {
            try readMaterials(alloc, materials_node, &local_materials);
        }

        const entity_id = try self.loadInstancer(alloc, root, parent, local_materials, graph, prototype);

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
        parent: Graph.Node,
        local_materials: LocalMaterials,
        graph: *Graph,
    ) !void {
        var prototypes: List(u32) = .empty;
        defer prototypes.deinit(alloc);

        if (value.object.get("prototypes")) |prototypes_node| {
            const proto_array = prototypes_node.array;
            prototypes = try List(u32).initCapacity(alloc, proto_array.items.len);

            for (proto_array.items) |proto_value| {
                const proto = self.loadEntity(alloc, proto_value, parent, local_materials, graph, true) catch continue;

                prototypes.appendAssumeCapacity(proto.entity_id);
            }
        }

        if (value.object.get("instances")) |instances_node| {
            const scene = &graph.scene;

            const proto_indices_value = instances_node.object.get("prototypes") orelse {
                log.err("Scatterer: No protype indices", .{});
                return;
            };

            const trafos_value = instances_node.object.get("transformations") orelse {
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

                _ = try graph.propSetTransformation(alloc, entity_id, trafo, parent, null);
            }
        }
    }

    fn setVisibility(prop: u32, value: std.json.Value, scene: *Scene) void {
        const in_camera = json.readBoolMember(value, "in_camera", true);
        const in_reflection = json.readBoolMember(value, "in_reflection", true);
        const shadow_catcher_light = json.readBoolMember(value, "shadow_catcher_light", false);

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
        if (local_materials.get(name)) |material_node| {
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

        if (value.object.get("parameters")) |parameters| {
            sky.setParameters(parameters);
        }

        return sky.sun;
    }
};
