const Vec4f = @import("vector4.zig").Vec4f;

pub const Ray = struct {
    origin: Vec4f,
    direction: Vec4f,

    pub fn init(origin: Vec4f, direction: Vec4f, min_t: f32, max_t: f32) Ray {
        return Ray{
            .origin = Vec4f.init3_1(origin, min_t),
            .direction = Vec4f.init3_1(direction, max_t),
        };
    }

    pub fn minT(self: Ray) f32 {
        return self.origin.v[3];
    }

    pub fn setMinT(self: *Ray, t: f32) void {
        self.origin.v[3] = t;
    }

    pub fn maxT(self: Ray) f32 {
        return self.direction.v[3];
    }

    pub fn setMaxT(self: *Ray, t: f32) void {
        self.direction.v[3] = t;
    }

    pub fn point(self: Ray, t: f32) Vec4f {
        return self.origin.add3(self.direction.mulScalar3(t));
    }
};
