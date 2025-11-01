const Cache = @import("cache.zig").Cache;
const Filesystem = @import("../file/system.zig").System;
const Image = @import("../image/image.zig").Image;
const ImageProvider = @import("../image/image_provider.zig").Provider;
const Images = Cache(Image, ImageProvider);
const Material = @import("../scene/material/material.zig").Material;
const Scene = @import("../scene/scene.zig").Scene;
const Shape = @import("../scene/shape/shape.zig").Shape;
const Instancer = @import("../scene/prop/instancer.zig").Instancer;
const Instancers = Cache(Instancer, void);
const Camera = @import("../camera/camera_base.zig").Base;

const base = @import("base");
const Threads = base.thread.Pool;
const Variants = base.memory.VariantMap;

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Error = error{
    UnknownResource,
};

pub const Manager = struct {
    pub const ShapeProvider = @import("../scene/shape/shape_provider.zig").Provider;
    pub const MaterialProvider = @import("../scene/material/material_provider.zig").Provider;

    const Shapes = Cache(Shape, ShapeProvider);
    const Materials = Cache(Material, MaterialProvider);

    pub const Null = 0xFFFFFFFF;

    scene: *Scene,
    threads: *Threads,

    fs: Filesystem,

    images: Images,
    materials: Materials,
    shapes: Shapes,
    instancers: Instancers,

    frame_start: u64 = undefined,
    frame_duration: u64 = undefined,

    const Self = @This();

    pub fn init(alloc: Allocator, io: Io, scene: *Scene, threads: *Threads) !Self {
        return Self{
            .scene = scene,
            .threads = threads,
            .fs = try Filesystem.init(alloc, io),
            .images = Images.init(.{}, &scene.images),
            .materials = Materials.init(.{}, &scene.materials),
            .shapes = Shapes.init(.{}, &scene.shapes),
            .instancers = Instancers.init({}, &scene.instancers),
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.shapes.deinit(alloc);
        self.materials.deinit(alloc);
        self.images.deinit(alloc);
        self.fs.deinit(alloc);
    }

    pub fn setFrameTime(self: *Self, frame: u32, camera: Camera) void {
        self.frame_start = @as(u64, frame) * camera.frame_step;
        self.frame_duration = camera.frame_duration;
    }

    pub fn loadFile(
        self: *Self,
        comptime T: type,
        alloc: Allocator,
        name: []const u8,
        options: Variants,
    ) !u32 {
        if (Image == T) {
            return self.images.loadFile(alloc, name, options, self);
        } else if (Material == T) {
            return self.materials.loadFile(alloc, name, options, self);
        } else if (Shape == T) {
            return self.shapes.loadFile(alloc, name, options, self);
        }

        return Error.UnknownResource;
    }

    pub fn loadData(
        self: *Self,
        comptime T: type,
        alloc: Allocator,
        id: u32,
        data: *align(8) const anyopaque,
        options: Variants,
    ) !u32 {
        if (Material == T) {
            return self.materials.loadData(alloc, id, data, options, self);
        } else if (Shape == T) {
            return self.shapes.loadData(alloc, id, data, options, self);
        }

        return Error.UnknownResource;
    }

    pub fn commitAsync(self: *Self) void {
        self.threads.waitAsync();

        self.shapes.provider.commitAsync(self);
    }

    pub fn get(self: *const Self, comptime T: type, id: u32) ?*T {
        if (Image == T) {
            return self.images.get(id);
        }

        if (Material == T) {
            return self.materials.get(id);
        }

        return null;
    }

    pub fn getByName(self: *const Self, comptime T: type, name: []const u8, options: Variants) ?u32 {
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
        self: *Self,
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

    pub fn reloadFrameDependant(self: *Self, alloc: Allocator) !bool {
        var deprecated = try self.images.reloadFrameDependant(alloc, self);

        deprecated = try self.shapes.reloadFrameDependant(alloc, self) or deprecated;

        return deprecated;
    }
};
