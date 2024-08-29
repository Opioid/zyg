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

    pub fn minT(self: Ray) f32 {
        return self.origin[3];
    }

    pub fn maxT(self: Ray) f32 {
        return self.direction[3];
    }

    pub fn setMinT(self: *Ray, t: f32) void {
        self.origin[3] = t;
    }

    pub fn setMaxT(self: *Ray, t: f32) void {
        self.direction[3] = t;
    }

    pub fn setMinMaxT(self: *Ray, min_t: f32, max_t: f32) void {
        self.origin[3] = min_t;
        self.direction[3] = max_t;
    }

    pub fn clipMaxT(self: *Ray, t: f32) void {
        const max_t = self.direction[3];
        self.direction[3] = mima.min(max_t, t);
    }

    pub fn point(self: Ray, t: f32) Vec4f {
        const p = self.origin + @as(Vec4f, @splat(t)) * self.direction;
        return .{ p[0], p[1], p[2], 0.0 };
    }
};
