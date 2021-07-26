const Cache = @import("cache.zig").Cache;

const Shape = @import("../scene/shape/shape.zig").Shape;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Null = 0xFFFFFFFF;

const Shapes = Cache(Shape);

pub const Manager = struct {
    shapes: Shapes,

    pub fn init(alloc: *Allocator) Manager {
        _ = alloc;
        return .{
            .shapes = Shapes.init(alloc),
        };
    }

    pub fn deinit(self: *Manager, alloc: *Allocator) void {
        self.shapes.deinit(alloc);
    }
};
