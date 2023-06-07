const cache = @import("cache.zig");
const Cache = cache.Cache;
const Filesystem = @import("../file/system.zig").System;
const Image = @import("../image/image.zig").Image;
const ImageProvider = @import("../image/image_provider.zig").Provider;
const Images = Cache(Image, ImageProvider);
const Material = @import("../scene/material/material.zig").Material;
pub const MaterialProvider = @import("../scene/material/material_provider.zig").Provider;
const Scene = @import("../scene/scene.zig").Scene;
const Shape = @import("../scene/shape/shape.zig").Shape;
const Materials = Cache(Material, MaterialProvider);
pub const TriangleMeshProvider = @import("../scene/shape/triangle/triangle_mesh_provider.zig").Provider;
const Shapes = Cache(Shape, TriangleMeshProvider);

const base = @import("base");
const Threads = base.thread.Pool;
const Variants = base.memory.VariantMap;

pub const Null = cache.Null;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    UnknownResource,
};

pub const Manager = struct {
    scene: *Scene,
    threads: *Threads,

    fs: Filesystem,

    images: Images,
    materials: Materials,
    shapes: Shapes,

    pub fn init(alloc: Allocator, scene: *Scene, threads: *Threads) !Manager {
        return Manager{
            .scene = scene,
            .threads = threads,
            .fs = try Filesystem.init(alloc),
            .images = Images.init(ImageProvider{}, &scene.images),
            .materials = Materials.init(MaterialProvider.init(alloc), &scene.materials),
            .shapes = Shapes.init(TriangleMeshProvider{}, &scene.shapes),
        };
    }

    pub fn deinit(self: *Manager, alloc: Allocator) void {
        self.shapes.deinit(alloc);
        self.materials.deinit(alloc);
        self.images.deinit(alloc);
        self.fs.deinit(alloc);
    }

    pub fn loadFile(
        self: *Manager,
        comptime T: type,
        alloc: Allocator,
        name: []const u8,
        options: Variants,
    ) !u32 {
        if (Image == T) {
            return try self.images.loadFile(alloc, name, options, self);
        } else if (Material == T) {
            return try self.materials.loadFile(alloc, name, options, self);
        } else if (Shape == T) {
            return try self.shapes.loadFile(alloc, name, options, self);
        }

        return Error.UnknownResource;
    }

    pub fn loadData(
        self: *Manager,
        comptime T: type,
        alloc: Allocator,
        id: u32,
        data: *align(8) const anyopaque,
        options: Variants,
    ) !u32 {
        if (Material == T) {
            return try self.materials.loadData(alloc, id, data, options, self);
        } else if (Shape == T) {
            return try self.shapes.loadData(alloc, id, data, options, self);
        }

        return Error.UnknownResource;
    }

    pub fn commitAsync(self: *Manager) void {
        self.threads.waitAsync();

        self.shapes.provider.commitAsync(self);
    }

    pub fn get(self: *const Manager, comptime T: type, id: u32) ?*T {
        if (Image == T) {
            return self.images.get(id);
        }

        if (Material == T) {
            return self.materials.get(id);
        }

        return null;
    }

    pub fn getByName(self: *const Manager, comptime T: type, name: []const u8, options: Variants) ?u32 {
        if (Image == T) {
            return self.images.getByName(name, options);
        } else if (Material == T) {
            return self.materials.getByName(name, options);
        } else if (Shape == T) {
            return self.shapes.getByName(name, options);
        }

        return null;
    }

    pub fn associate(
        self: *Manager,
        comptime T: type,
        alloc: Allocator,
        id: u32,
        name: []const u8,
        options: Variants,
    ) !void {
        if (Image == T) {
            try self.images.associate(alloc, id, name, options);
        } else if (Material == T) {
            try self.materials.associate(alloc, id, name, options);
        } else if (Shape == T) {
            try self.shapes.loadData(alloc, id, name, options);
        }

        return Error.UnknownResource;
    }
};
