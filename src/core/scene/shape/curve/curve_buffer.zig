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

    pub fn copy(self: Buffer, points: [*]f32, widths: [*]f32, count: u32) void {
        return switch (self) {
            inline else => |v| v.copy(points, widths, count),
        };
    }
};

pub const Separate = struct {
    points: []const Pack3f,

    widths: []const f32,

    own: bool,

    const Self = @This();

    pub fn initOwned(points: []Pack3f, widths: []f32) Self {
        return .{
            .points = points,
            .widths = widths,
            .own = true,
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        if (self.own) {
            alloc.free(self.widths);
            alloc.free(self.points);
        }
    }

    pub fn copy(self: Self, points: [*]f32, widths: [*]f32, count: u32) void {
        const num_components = 4 * 3 * count;
        @memcpy(points[0..num_components], @as([*]const f32, @ptrCast(self.points.ptr))[0..num_components]);

        const num_widths = 2 * count;
        @memcpy(widths[0..num_widths], self.widths[0..num_widths]);
    }
};
