const cache = @import("cache.zig");
const Cache = cache.Cache;
const Filesystem = @import("../file/system.zig").System;
const Material = @import("../scene/material/material.zig").Material;
const Material_provider = @import("../scene/material/provider.zig").Provider;
const Shape = @import("../scene/shape/shape.zig").Shape;
const Materials = Cache(Material, Material_provider);
const Triangle_mesh_provider = @import("../scene/shape/triangle/mesh_provider.zig").Provider;
const Shapes = Cache(Shape, Triangle_mesh_provider);

usingnamespace @import("base");

pub const Null = cache.Null;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    UnknownResource,
};

pub const Manager = struct {
    threads: *thread.Pool,

    fs: Filesystem = .{},

    materials: Materials,
    shapes: Shapes,

    pub fn init(alloc: *Allocator, threads: *thread.Pool) Manager {
        return .{
            .threads = threads,
            .materials = Materials.init(alloc, Material_provider{}),
            .shapes = Shapes.init(alloc, Triangle_mesh_provider{}),
        };
    }

    pub fn deinit(self: *Manager, alloc: *Allocator) void {
        self.shapes.deinit(alloc);
        self.materials.deinit(alloc);
        self.fs.deinit(alloc);
    }

    pub fn loadFile(self: *Manager, comptime T: type, alloc: *Allocator, name: []const u8) !u32 {
        if (Material == T) {
            return try self.materials.loadFile(alloc, name, self);
        }

        if (Shape == T) {
            return try self.shapes.loadFile(alloc, name, self);
        }

        return Error.UnknownResource;
    }

    pub fn loadData(self: *Manager, comptime T: type, alloc: *Allocator, name: []const u8, data: usize) !u32 {
        if (Material == T) {
            return try self.materials.loadData(alloc, name, data, self);
        }

        if (Shape == T) {
            return try self.shapes.loadData(alloc, name, data, self);
        }

        return Error.UnknownResource;
    }

    pub fn get(self: Manager, comptime T: type, name: []const u8) ?u32 {
        if (Material == T) {
            return self.materials.get(name);
        }

        if (Shape == T) {
            return self.shapes.get(name);
        }

        return null;
    }
};
