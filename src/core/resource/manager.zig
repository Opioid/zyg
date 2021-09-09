const cache = @import("cache.zig");
const Cache = cache.Cache;
const Filesystem = @import("../file/system.zig").System;
const Image = @import("../image/image.zig").Image;
const ImageProvider = @import("../image/provider.zig").Provider;
const Images = Cache(Image, ImageProvider);
const Material = @import("../scene/material/material.zig").Material;
const MaterialProvider = @import("../scene/material/provider.zig").Provider;
const Shape = @import("../scene/shape/shape.zig").Shape;
const Materials = Cache(Material, MaterialProvider);
const TriangleMeshProvider = @import("../scene/shape/triangle/mesh_provider.zig").Provider;
const Shapes = Cache(Shape, TriangleMeshProvider);

const base = @import("base");
const Threads = base.thread.Pool;

pub const Null = cache.Null;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    UnknownResource,
};

pub const Manager = struct {
    threads: *Threads,

    fs: Filesystem = .{},

    images: Images,
    materials: Materials,
    shapes: Shapes,

    pub fn init(alloc: *Allocator, threads: *Threads) Manager {
        return .{
            .threads = threads,
            .images = Images.init(alloc, ImageProvider{}),
            .materials = Materials.init(alloc, MaterialProvider{}),
            .shapes = Shapes.init(alloc, TriangleMeshProvider{}),
        };
    }

    pub fn deinit(self: *Manager, alloc: *Allocator) void {
        self.shapes.deinit(alloc);
        self.materials.deinit(alloc);
        self.images.deinit(alloc);
        self.fs.deinit(alloc);
    }

    pub fn loadFile(self: *Manager, comptime T: type, alloc: *Allocator, name: []const u8) !u32 {
        if (Image == T) {
            return try self.images.loadFile(alloc, name, self);
        }

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

    pub fn get(self: Manager, comptime T: type, id: u32) ?*T {
        if (Image == T) {
            return self.images.get(id);
        }

        return null;
    }

    pub fn getByName(self: Manager, comptime T: type, name: []const u8) ?u32 {
        if (Image == T) {
            return self.images.getByName(name);
        }

        if (Material == T) {
            return self.materials.getByName(name);
        }

        if (Shape == T) {
            return self.shapes.getByName(name);
        }

        return null;
    }
};
