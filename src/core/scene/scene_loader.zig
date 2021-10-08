pub const Scene = @import("scene.zig").Scene;
pub const prp = @import("prop/prop.zig");
const resource = @import("../resource/manager.zig");
const Resources = resource.Manager;
const anim = @import("animation/loader.zig");
const Take = @import("../take/take.zig").Take;
const Shape = @import("shape/shape.zig").Shape;
const Material = @import("material/material.zig").Material;
pub const mat = @import("material/provider.zig");

const base = @import("base");
const json = base.json;
const string = base.string;
const math = base.math;
const Vec4f = math.Vec4f;
const Transformation = math.Transformation;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Loader = struct {
    pub const Error = error{
        OutOfMemory,
    };

    resources: *Resources,

    null_shape: u32,
    disk: u32,
    infinite_sphere: u32,
    plane: u32,
    rectangle: u32,
    sphere: u32,

    fallback_material: u32,

    materials: std.ArrayListUnmanaged(u32) = .{},

    const LocalMaterials = struct {
        materials: std.StringHashMap(*std.json.Value),

        pub fn init(alloc: *Allocator) LocalMaterials {
            return .{ .materials = std.StringHashMap(*std.json.Value).init(alloc) };
        }

        pub fn deinit(self: *LocalMaterials) void {
            self.materials.deinit();
        }
    };

    pub fn init(alloc: *Allocator, resources: *Resources, fallback_material: Material) Loader {
        return Loader{
            .resources = resources,
            .null_shape = resources.shapes.store(alloc, Shape{ .Null = {} }),
            .disk = resources.shapes.store(alloc, Shape{ .Disk = .{} }),
            .infinite_sphere = resources.shapes.store(alloc, Shape{ .InfiniteSphere = .{} }),
            .plane = resources.shapes.store(alloc, Shape{ .Plane = .{} }),
            .rectangle = resources.shapes.store(alloc, Shape{ .Rectangle = .{} }),
            .sphere = resources.shapes.store(alloc, Shape{ .Sphere = .{} }),
            .fallback_material = resources.materials.store(alloc, fallback_material),
        };
    }

    pub fn deinit(self: *Loader, alloc: *Allocator) void {
        self.materials.deinit(alloc);
    }

    pub fn load(self: *Loader, alloc: *Allocator, filename: []const u8, take: Take, scene: *Scene) !void {
        const camera = take.view.camera;

        scene.calculateNumInterpolationFrames(camera.frame_step, camera.frame_duration);

        const fs = &self.resources.fs;

        var stream = try fs.readStream(alloc, filename);
        defer stream.deinit();

        const buffer = try stream.reader.unbuffered_reader.readAllAlloc(alloc, std.math.maxInt(u64));
        defer alloc.free(buffer);

        var parser = std.json.Parser.init(alloc, false);
        defer parser.deinit();

        var document = try parser.parse(buffer);
        defer document.deinit();

        const root = document.root;

        var local_materials = LocalMaterials.init(alloc);
        defer local_materials.deinit();

        if (root.Object.get("materials")) |materials_node| {
            try readMaterials(materials_node, &local_materials);
        }

        try fs.pushMount(alloc, string.parentDirectory(fs.lastResolvedName()));

        const parent_id: u32 = prp.Null;

        const parent_trafo = Transformation{
            .position = @splat(4, @as(f32, 0.0)),
            .scale = @splat(4, @as(f32, 1.0)),
            .rotation = math.quaternion.identity,
        };

        var iter = root.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "entities", entry.key_ptr.*)) {
                try self.loadEntities(
                    alloc,
                    entry.value_ptr.*,
                    parent_id,
                    parent_trafo,
                    local_materials,
                    scene,
                );
            }
        }

        fs.popMount(alloc);
    }

    fn readMaterials(value: std.json.Value, local_materials: *LocalMaterials) !void {
        _ = local_materials;

        for (value.Array.items) |*m| {
            const name_node = m.Object.get("name") orelse continue;

            try local_materials.materials.put(name_node.String, m);
        }
    }

    fn loadEntities(
        self: *Loader,
        alloc: *Allocator,
        value: std.json.Value,
        parent_id: u32,
        parent_trafo: Transformation,
        local_materials: LocalMaterials,
        scene: *Scene,
    ) Error!void {
        for (value.Array.items) |entity| {
            const type_node = entity.Object.get("type") orelse continue;
            const type_name = type_node.String;

            var entity_id: u32 = prp.Null;

            if (std.mem.eql(u8, "Light", type_name)) {
                const prop_id = try self.loadProp(alloc, entity, local_materials, scene);

                if (prp.Null != prop_id and scene.prop(prop_id).visibleInReflection()) {
                    try scene.createLight(alloc, prop_id);
                }

                entity_id = prop_id;
            } else if (std.mem.eql(u8, "Prop", type_name)) {
                entity_id = try self.loadProp(alloc, entity, local_materials, scene);
            } else if (std.mem.eql(u8, "Dummy", type_name)) {
                entity_id = try scene.createEntity(alloc);
            }

            if (prp.Null == entity_id) {
                continue;
            }

            var trafo = Transformation{
                .position = @splat(4, @as(f32, 0.0)),
                .scale = @splat(4, @as(f32, 1.0)),
                .rotation = math.quaternion.identity,
            };

            var animation_ptr: ?*std.json.Value = null;
            var children_ptr: ?*std.json.Value = null;

            var iter = entity.Object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "transformation", entry.key_ptr.*)) {
                    json.readTransformation(entry.value_ptr.*, &trafo);
                } else if (std.mem.eql(u8, "animation", entry.key_ptr.*)) {
                    animation_ptr = entry.value_ptr;
                } else if (std.mem.eql(u8, "entities", entry.key_ptr.*)) {
                    children_ptr = entry.value_ptr;
                }
            }

            const animation = if (animation_ptr) |animation|
                try anim.load(alloc, animation.*, trafo, entity_id, scene)
            else
                false;

            if (prp.Null != parent_id) {
                try scene.propSerializeChild(alloc, parent_id, entity_id);
            }

            if (!animation) {
                if (scene.propHasAnimatedFrames(entity_id)) {
                    scene.propSetTransformation(entity_id, trafo);
                } else {
                    if (prp.Null != parent_id) {
                        trafo = parent_trafo.transform(trafo);
                    }
                    scene.propSetWorldTransformation(entity_id, trafo);
                }
            }

            if (children_ptr) |children| {
                try self.loadEntities(
                    alloc,
                    children.*,
                    entity_id,
                    trafo,
                    local_materials,
                    scene,
                );
            }
        }
    }

    fn loadProp(
        self: *Loader,
        alloc: *Allocator,
        value: std.json.Value,
        local_materials: LocalMaterials,
        scene: *Scene,
    ) !u32 {
        var shape: u32 = resource.Null;

        var materials_value_ptr: ?*std.json.Value = null;
        var visibility_ptr: ?*std.json.Value = null;

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "shape", entry.key_ptr.*)) {
                shape = self.loadShape(alloc, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "materials", entry.key_ptr.*)) {
                materials_value_ptr = entry.value_ptr;
            } else if (std.mem.eql(u8, "visibility", entry.key_ptr.*)) {
                visibility_ptr = entry.value_ptr;
            }
        }

        if (resource.Null == shape) {
            return prp.Null;
        }

        const num_materials = scene.shape(shape).numMaterials();

        try self.materials.ensureTotalCapacity(alloc, num_materials);
        self.materials.clearRetainingCapacity();

        if (materials_value_ptr) |materials_value| {
            try self.loadMaterials(alloc, materials_value.*, local_materials);
        }

        while (self.materials.items.len < num_materials) {
            self.materials.appendAssumeCapacity(self.fallback_material);
        }

        const prop = try scene.createProp(alloc, shape, self.materials.items);

        if (visibility_ptr) |visibility| {
            setVisibility(prop, visibility.*, scene);
        }

        return prop;
    }

    fn setVisibility(prop: u32, value: std.json.Value, scene: *Scene) void {
        var in_camera = true;
        var in_reflection = true;
        var in_shadow = true;

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "in_camera", entry.key_ptr.*)) {
                in_camera = json.readBool(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "in_reflection", entry.key_ptr.*)) {
                in_reflection = json.readBool(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "in_shadow", entry.key_ptr.*)) {
                in_shadow = json.readBool(entry.value_ptr.*);
            }
        }

        scene.propSetVisibility(prop, in_camera, in_reflection, in_shadow);
    }

    fn loadShape(self: Loader, alloc: *Allocator, value: std.json.Value) u32 {
        const type_name = json.readStringMember(value, "type", "");
        if (type_name.len > 0) {
            return self.getShape(type_name);
        }

        const file = json.readStringMember(value, "file", "");
        if (file.len > 0) {
            const id = self.resources.loadFile(Shape, alloc, file, .{}) catch |e| {
                std.debug.print("Could not load file \"{s}\": {}\n", .{ file, e });
                return resource.Null;
            };

            return id;
        }

        return resource.Null;
    }

    fn getShape(self: Loader, type_name: []const u8) u32 {
        if (std.mem.eql(u8, "Disk", type_name)) {
            return self.disk;
        }

        if (std.mem.eql(u8, "Infinite_sphere", type_name)) {
            return self.infinite_sphere;
        }

        if (std.mem.eql(u8, "Plane", type_name)) {
            return self.plane;
        }

        if (std.mem.eql(u8, "Rectangle", type_name)) {
            return self.rectangle;
        }

        if (std.mem.eql(u8, "Sphere", type_name)) {
            return self.sphere;
        }

        return resource.Null;
    }

    fn loadMaterials(
        self: *Loader,
        alloc: *Allocator,
        value: std.json.Value,
        local_materials: LocalMaterials,
    ) !void {
        for (value.Array.items) |m| {
            try self.materials.append(alloc, self.loadMaterial(alloc, m.String, local_materials));

            if (self.materials.capacity == self.materials.items.len) {
                return;
            }
        }
    }

    fn loadMaterial(
        self: Loader,
        alloc: *Allocator,
        name: []const u8,
        local_materials: LocalMaterials,
    ) u32 {
        // First, check if we maybe already have cached the material.
        if (self.resources.getByName(Material, name)) |material| {
            return material;
        }

        // Otherwise, see if it is among the locally defined materials.
        if (local_materials.materials.get(name)) |material_node| {
            const data = @ptrToInt(material_node);

            const material = self.resources.loadData(Material, alloc, name, data, .{}) catch resource.Null;
            if (resource.Null != material) {
                if (self.resources.get(Material, material)) |mp| {
                    mp.commit();
                }
                return material;
            }
        }

        // Lastly, try loading the material from the filesystem.
        const material = self.resources.loadFile(Material, alloc, name, .{}) catch {
            std.debug.print("Using fallback for material \"{s}\"\n", .{name});
            return self.fallback_material;
        };

        if (self.resources.get(Material, material)) |mp| mp.commit();
        return material;
    }
};
