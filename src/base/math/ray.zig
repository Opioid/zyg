const math = @import("vector4.zig");
const Vec4f = math.Vec4f;

pub const Ray = struct {
    origin: Vec4f,
    direction: Vec4f,
    inv_direction: Vec4f,

    pub fn init(origin: Vec4f, direction: Vec4f, min_t: f32, max_t: f32) Ray {
        return .{
            .origin = .{ origin[0], origin[1], origin[2], min_t },
            .direction = .{ direction[0], direction[1], direction[2], max_t },
            .inv_direction = math.reciprocal3(direction),
        };
    }

    pub fn setDirection(self: *Ray, direction: Vec4f) void {
        self.direction = .{ direction[0], direction[1], direction[2], self.direction[3] };
        self.inv_direction = math.reciprocal3(direction);
    }

    pub fn minT(self: Ray) f32 {
        return self.origin[3];
    }

    pub fn setMinT(self: *Ray, t: f32) void {
        self.origin[3] = t;
    }

    pub fn maxT(self: Ray) f32 {
        return self.direction[3];
    }

    pub fn setMaxT(self: *Ray, t: f32) void {
        self.direction[3] = t;
    }

    pub fn point(self: Ray, t: f32) Vec4f {
        return self.origin + @splat(4, t) * self.direction;
    }
};
