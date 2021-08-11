const cache = @import("cache.zig");
const Cache = cache.Cache;
const Filesystem = @import("../file/system.zig").System;
const Shape = @import("../scene/shape/shape.zig").Shape;
usingnamespace @import("base");

pub const Triangle_mesh_provider = @import("../scene/shape/triangle/mesh_provider.zig").Provider;
pub const Shapes = Cache(Shape, Triangle_mesh_provider);
pub const Null = cache.Null;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    UnknownResource,
};

pub const Manager = struct {
    threads: *thread.Pool,

    fs: Filesystem = .{},

    shapes: Shapes = undefined,

    pub fn init(threads: *thread.Pool) Manager {
        return .{ .threads = threads };
    }

    pub fn deinit(self: *Manager, alloc: *Allocator) void {
        self.shapes.deinit(alloc);

        self.fs.deinit(alloc);
    }

    pub fn load(self: *Manager, comptime T: type, alloc: *Allocator, name: []const u8) !u32 {
        if (Shape == T) {
            return try self.shapes.load(alloc, name, self);
        }

        return Error.UnknownResource;
    }
};
