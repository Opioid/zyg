const math = @import("vector4.zig");
const Vec4f = math.Vec4f;

pub const Ray = struct {
    origin: Vec4f,
    direction: Vec4f,
    inv_direction: Vec4f,

    pub fn init(origin: Vec4f, direction: Vec4f, min_t: f32, max_t: f32) Ray {
        const id = math.reciprocal3(.{ direction[0], direction[1], direction[2], 1.0 });
        return .{
            .origin = .{ origin[0], origin[1], origin[2], min_t },
            .direction = direction,
            .inv_direction = Vec4f{ id[0], id[1], id[2], max_t },
        };
    }

    pub fn setDirection(self: *Ray, direction: Vec4f) void {
        const id = math.reciprocal3(.{ direction[0], direction[1], direction[2], 1.0 });
        const max_t = self.inv_direction[3];

        self.direction = direction;
        self.inv_direction = Vec4f{ id[0], id[1], id[2], max_t };
    }

    pub fn minT(self: Ray) f32 {
        return self.origin[3];
    }

    pub fn setMinT(self: *Ray, t: f32) void {
        self.origin[3] = t;
    }

    pub fn maxT(self: Ray) f32 {
        return self.inv_direction[3];
    }

    pub fn setMaxT(self: *Ray, t: f32) void {
        self.inv_direction[3] = t;
    }

    pub fn clipMaxT(self: *Ray, t: f32) void {
        const max_t = self.inv_direction[3];
        self.inv_direction[3] = @minimum(max_t, t);
    }

    pub fn point(self: Ray, t: f32) Vec4f {
        return self.origin + @splat(4, t) * self.direction;
    }
};
