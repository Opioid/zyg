pub const Scene = @import("scene.zig").Scene;
pub const prp = @import("prop/prop.zig");
const resource = @import("../resource/manager.zig");
const Resources = resource.Manager;
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
    resources: *Resources,

    null_shape: u32,
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
            .rectangle = resources.shapes.store(alloc, Shape{ .Rectangle = .{} }),
            .plane = resources.shapes.store(alloc, Shape{ .Plane = .{} }),
            .sphere = resources.shapes.store(alloc, Shape{ .Sphere = .{} }),
            .fallback_material = resources.materials.store(alloc, fallback_material),
        };
    }

    pub fn deinit(self: *Loader, alloc: *Allocator) void {
        self.materials.deinit(alloc);
    }

    pub fn load(self: *Loader, alloc: *Allocator, filename: []const u8, scene: *Scene) !void {
        const fs = &self.resources.fs;

        var stream = try fs.readStream(filename);
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

        var iter = root.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "entities", entry.key_ptr.*)) {
                try self.loadEntities(alloc, entry.value_ptr.*, local_materials, scene);
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
        local_materials: LocalMaterials,
        scene: *Scene,
    ) !void {
        for (value.Array.items) |entity| {
            const type_node = entity.Object.get("type") orelse continue;
            const type_name = type_node.String;

            var entity_id: u32 = prp.Null;

            if (std.mem.eql(u8, "Light", type_name)) {
                const prop_id = try self.loadProp(alloc, entity, local_materials, scene);

                if (prp.Null != prop_id) {
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
                .position = Vec4f.init1(0.0),
                .scale = Vec4f.init1(1.0),
                .rotation = math.quaternion.identity,
            };

            var iter = entity.Object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "transformation", entry.key_ptr.*)) {
                    json.readTransformation(entry.value_ptr.*, &trafo);
                }
            }

            scene.propSetWorldTransformation(entity_id, trafo);
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

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "shape", entry.key_ptr.*)) {
                shape = self.loadShape(alloc, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "materials", entry.key_ptr.*)) {
                materials_value_ptr = entry.value_ptr;
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

        // if (self.materals.len > 1 or)

        while (self.materials.items.len < num_materials) {
            self.materials.appendAssumeCapacity(self.fallback_material);
        }

        return try scene.createProp(alloc, shape, self.materials.items);
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
                return material;
            }
        }

        // Lastly, try loading the material from the filesystem.
        const material = self.resources.loadFile(Material, alloc, name, .{}) catch {
            std.debug.print("Using fallback for material \"{s}\"\n", .{name});

            return self.fallback_material;
        };

        return material;
    }
};
