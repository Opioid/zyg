const math = @import("vector4.zig");
const Vec4f = math.Vec4f;
const mima = @import("minmax.zig");

const std = @import("std");

pub const Ray = struct {
    origin: Vec4f,
    direction: Vec4f,
    inv_direction: Vec4f,

    pub fn init(origin: Vec4f, direction: Vec4f, min_t: f32, max_t: f32) Ray {
        const id = math.reciprocal3(.{ direction[0], direction[1], direction[2], 1.0 });
        return .{
            .origin = .{ origin[0], origin[1], origin[2], min_t },
            .direction = .{ direction[0], direction[1], direction[2], max_t },
            .inv_direction = id,
        };
    }

    pub fn setDirection(self: *Ray, direction: Vec4f, max_t: f32) void {
        const id = math.reciprocal3(.{ direction[0], direction[1], direction[2], 1.0 });
        self.direction = .{ direction[0], direction[1], direction[2], max_t };
        self.inv_direction = id;
    }

    pub inline fn minT(self: Ray) f32 {
        return self.origin[3];
    }

    pub inline fn maxT(self: Ray) f32 {
        return self.direction[3];
    }

    pub inline fn setMinT(self: *Ray, t: f32) void {
        self.origin[3] = t;
    }

    pub inline fn setMaxT(self: *Ray, t: f32) void {
        self.direction[3] = t;
    }

    pub inline fn setMinMaxT(self: *Ray, min_t: f32, max_t: f32) void {
        self.origin[3] = min_t;
        self.direction[3] = max_t;
    }

    pub inline fn clipMaxT(self: *Ray, t: f32) void {
        const max_t = self.direction[3];
        self.direction[3] = mima.min(max_t, t);
    }

    pub inline fn point(self: Ray, t: f32) Vec4f {
        return self.origin + @splat(4, t) * self.direction;
    }
};
