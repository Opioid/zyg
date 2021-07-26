pub const Scene = @import("scene.zig").Scene;
pub const prp = @import("prop/prop.zig");
const resource = @import("../resource/manager.zig");
const shp = @import("shape/shape.zig");

const base = @import("base");
usingnamespace base;
usingnamespace base.math;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Loader = struct {
    resources: *resource.Manager,

    null_shape: u32,
    plane: u32,
    sphere: u32,

    pub fn init(alloc: *Allocator, resources: *resource.Manager) !Loader {
        return Loader{
            .resources = resources,
            .null_shape = try resources.shapes.store(alloc, shp.Shape{ .Null = {} }),
            .plane = try resources.shapes.store(alloc, shp.Shape{ .Plane = shp.Plane{} }),
            .sphere = try resources.shapes.store(alloc, shp.Shape{ .Sphere = shp.Sphere{} }),
        };
    }

    pub fn load(self: *Loader, alloc: *Allocator, scene: *Scene) !void {
        var file = try std.fs.cwd().openFile("imrod.scene", .{});
        defer file.close();

        const reader = file.reader();

        const buffer = try reader.readAllAlloc(alloc, std.math.maxInt(u64));
        defer alloc.free(buffer);

        var parser = std.json.Parser.init(alloc, false);
        defer parser.deinit();

        var document = try parser.parse(buffer);
        defer document.deinit();

        const root = document.root;

        var iter = root.Object.iterator();

        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "entities", entry.key_ptr.*)) {
                try self.loadEntities(alloc, entry.value_ptr.*, scene);
            }
        }
    }

    fn loadEntities(self: *Loader, alloc: *Allocator, value: std.json.Value, scene: *Scene) !void {
        for (value.Array.items) |entity| {
            const type_node = entity.Object.get("type") orelse continue;
            const type_name = type_node.String;

            var entity_id: u32 = prp.Null;

            if (std.mem.eql(u8, "Light", type_name)) {
                std.debug.print("A light \n", .{});
                entity_id = self.loadProp(alloc, entity, scene);
            } else if (std.mem.eql(u8, "Prop", type_name)) {
                entity_id = self.loadProp(alloc, entity, scene);
            } else if (std.mem.eql(u8, "Dummy", type_name)) {
                entity_id = scene.createEntity(alloc);
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

    fn loadProp(self: *Loader, alloc: *Allocator, value: std.json.Value, scene: *Scene) u32 {
        var shape: u32 = resource.Null;

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "shape", entry.key_ptr.*)) {
                shape = self.loadShape(alloc, entry.value_ptr.*);
            }
        }

        if (resource.Null == shape) {
            return prp.Null;
        }

        return scene.createProp(alloc, shape);
    }

    fn loadShape(self: *Loader, alloc: *Allocator, value: std.json.Value) u32 {
        const type_name = json.readStringMember(value, "type", "");
        if (type_name.len > 0) {
            return self.getShape(type_name);
        }

        // const file = json.readStringMember(value, "file", "");
        // if (type_name.len > 0) {
        //     return file(type_name);
        // }

        _ = alloc;

        return resource.Null;
    }

    fn getShape(self: *Loader, type_name: []const u8) u32 {
        if (std.mem.eql(u8, "Plane", type_name)) {
            return self.plane;
        }

        // if (std.mem.eql(u8, "Rectangle", type_name)) {
        //     return 0;
        // }

        if (std.mem.eql(u8, "Sphere", type_name)) {
            return self.sphere;
        }

        return resource.Null;
    }
};
