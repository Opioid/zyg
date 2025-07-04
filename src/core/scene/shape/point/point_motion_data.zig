const base = @import("base");
const math = base.math;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MotionData = struct {
    num_vertices: u32 = 0,

    radius: f32 = undefined,

    positions: [*]f32 = undefined,
    velocities: [*]f32 = undefined,

    const Self = @This();

    pub fn allocatePoints(self: *Self, alloc: Allocator, radius: f32, positions: []Pack3f, velocities: []Pack3f) !void {
        const num_vertices: u32 = @truncate(positions.len);
        const num_components = num_vertices * 3;

        self.num_vertices = num_vertices;
        self.radius = radius;

        self.positions = (try alloc.alloc(f32, num_components + 1)).ptr;
        self.velocities = (try alloc.alloc(f32, num_components + 1)).ptr;

        @memcpy(self.positions[0..num_components], @as([*]const f32, @ptrCast(positions.ptr))[0..num_components]);
        @memcpy(self.velocities[0..num_components], @as([*]const f32, @ptrCast(velocities.ptr))[0..num_components]);

        self.positions[num_components] = 0.0;
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        const num_components = self.num_vertices * 3 + 1;
        alloc.free(self.velocities[0..num_components]);
        alloc.free(self.positions[0..num_components]);
    }

    pub inline fn position(self: Self, index: u32) Vec4f {
        return self.positions[index * 3 ..][0..4].*;
    }

    pub fn positionAt(self: Self, index: u32, time: f32) Vec4f {
        const pos: Vec4f = self.positions[index * 3 ..][0..4].*;
        const vel: Vec4f = self.velocities[index * 3 ..][0..4].*;
        return pos + math.lerp(@as(Vec4f, @splat(0.0)), vel, @as(Vec4f, @splat(time)));
    }
};
