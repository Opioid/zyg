const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayList;

pub const Model = struct {
    pub const Topology = enum {
        PointList,
        TriangleList,
    };

    pub const Part = struct {
        start_index: u32,
        num_indices: u32,
        material_index: u32,
    };

    frame_duration: u64 = 0,

    parts: []Part = &.{},
    indices: []u32 = &.{},
    positions: List([]Pack3f) = .empty,
    normals: List([]Pack3f) = .empty,
    uvs: []Vec2f = &.{},

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.uvs);

        for (self.normals.items) |n| {
            alloc.free(n);
        }
        self.normals.deinit(alloc);

        for (self.positions.items) |p| {
            alloc.free(p);
        }
        self.positions.deinit(alloc);

        alloc.free(self.indices);
        alloc.free(self.parts);
    }
};
