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

    pub fn numCurves(self: Buffer) u32 {
        return switch (self) {
            inline else => |v| v.numCurves(),
        };
    }

    pub fn copy(self: Buffer, points: [*]f32, widths: [*]f32, count: u32) void {
        return switch (self) {
            inline else => |v| v.copy(points, widths, count),
        };
    }

    pub fn curvePoints(self: Buffer, id: u32) [4]Vec4f {
        return switch (self) {
            inline else => |v| v.curvePoints(id),
        };
    }

    pub fn curveWidth(self: Buffer, id: u32) Vec2f {
        return switch (self) {
            inline else => |v| v.curveWidth(id),
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

    pub fn numCurves(self: Self) u32 {
        //   return @intCast(self.points.len / 4);

        const nc: u32 = @intCast(self.points.len / 4);

        return @min(nc, nc / 1);
    }

    pub fn copy(self: Self, points: [*]f32, widths: [*]f32, count: u32) void {
        const num_components = 4 * 3 * count;
        @memcpy(points[0..num_components], @as([*]const f32, @ptrCast(self.points.ptr))[0..num_components]);

        const num_widths = 2 * count;
        @memcpy(widths[0..num_widths], self.widths[0..num_widths]);
    }

    pub fn curvePoints(self: Self, id: u32) [4]Vec4f {
        const offset = id * 4;

        return .{
            math.vec3fTo4f(self.points[offset + 0]),
            math.vec3fTo4f(self.points[offset + 1]),
            math.vec3fTo4f(self.points[offset + 2]),
            math.vec3fTo4f(self.points[offset + 3]),
        };
    }

    pub fn curveWidth(self: Self, id: u32) Vec2f {
        const offset = id * 2;

        return .{ self.widths[offset + 0], self.widths[offset + 1] };
    }
};
