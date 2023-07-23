const math = @import("base").math;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Buffer = union(enum) {
    Separate: Separate,

    pub fn deinit(self: *Buffer, alloc: Allocator) void {
        return switch (self.*) {
            inline else => |*v| v.deinit(alloc),
        };
    }

    pub fn copy(self: Buffer, positions: [*]f32, widths: [*]f32, count: u32) void {
        return switch (self) {
            inline else => |v| v.copy(positions, frames, uvs, count),
        };
    }
};

pub const Separate = struct {
    positions: []const Pack3f,

    widths: []const f32,

    own: bool,

    const Self = @This();

    pub fn initOwned(positions: []Pack3f, widths: []f32) Self {
        return .{
            .positions = positions,
            .widths = widths,
            .own = true,
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        if (self.own) {
            alloc.free(self.widths);
            alloc.free(self.positions);
        }
    }

    pub fn copy(self: Self, positions: [*]f32, widths: [*]f32, count: u32) void {
        @memcpy(positions[0 .. 4 * 3 * count], @as(f32*, @ptrCast(self.positions)));

        @memcpy(widths[0 .. 2 * count], self.widths);
    }
};
