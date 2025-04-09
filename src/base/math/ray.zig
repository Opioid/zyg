const math = @import("vector4.zig");
const Vec4f = math.Vec4f;
const mima = @import("minmax.zig");

pub const Ray = struct {
    origin: Vec4f,
    direction: Vec4f,
    inv_direction: Vec4f,
    min_t: f32,
    max_t: f32,

    pub fn init(origin: Vec4f, direction: Vec4f, min_t: f32, max_t: f32) Ray {
        const id = math.reciprocal3(.{ direction[0], direction[1], direction[2], 1.0 });
        return .{
            .origin = origin,
            .direction = direction,
            .inv_direction = id,
            .min_t = min_t,
            .max_t = max_t,
        };
    }

    pub fn setMinMaxT(self: *Ray, min_t: f32, max_t: f32) void {
        self.min_t = min_t;
        self.max_t = max_t;
    }

    pub fn point(self: Ray, t: f32) Vec4f {
        return self.origin + @as(Vec4f, @splat(t)) * self.direction;
    }
};
