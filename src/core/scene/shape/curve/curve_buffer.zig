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

    pub fn numPoints(self: Buffer) u32 {
        return switch (self) {
            inline else => |v| v.numPoints(),
        };
    }

    pub fn numWidths(self: Buffer) u32 {
        return switch (self) {
            inline else => |v| v.numWidths(),
        };
    }

    pub fn copy(self: Buffer, points: [*]f32, widths: [*]f32) void {
        return switch (self) {
            inline else => |v| v.copy(points, widths),
        };
    }

    pub fn curvePoints(self: Buffer, index: u32) [4]Vec4f {
        return switch (self) {
            inline else => |v| v.curvePoints(index),
        };
    }

    pub fn curveWidth(self: Buffer, index: u32) Vec2f {
        return switch (self) {
            inline else => |v| v.curveWidth(index),
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

    pub fn numPoints(self: Self) u32 {
        return @intCast(self.points.len);
    }

    pub fn numWidths(self: Self) u32 {
        return @intCast(self.widths.len);
    }

    pub fn copy(self: Self, points: [*]f32, widths: [*]f32) void {
        const num_components = self.points.len * 3;
        @memcpy(points[0..num_components], @as([*]const f32, @ptrCast(self.points.ptr))[0..num_components]);

        @memcpy(widths[0..self.widths.len], self.widths);
    }

    pub fn curvePoints(self: Self, index: u32) [4]Vec4f {
        return .{
            math.vec3fTo4f(self.points[index + 0]),
            math.vec3fTo4f(self.points[index + 1]),
            math.vec3fTo4f(self.points[index + 2]),
            math.vec3fTo4f(self.points[index + 3]),
        };
    }

    pub fn curveWidth(self: Self, index: u32) Vec2f {
        return .{ self.widths[index + 0], self.widths[index + 1] };
    }
};
