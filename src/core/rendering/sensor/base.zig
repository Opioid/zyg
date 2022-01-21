const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;

pub const Base = struct {
    dimensions: Vec2i = @splat(2, @as(i32, 0)),

    max: f32,

    pub fn clamp(self: Base, color: Vec4f) Vec4f {
        const mc = math.maxComponent3(color);

        if (mc > self.max) {
            const r = self.max / mc;
            const s = @splat(4, r) * color;
            return .{ s[0], s[1], s[2], color[3] };
        }

        return color;
    }
};
