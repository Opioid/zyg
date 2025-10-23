const Vec2f = @import("vector2.zig").Vec2f;

pub const Bounds2f = struct {
    bounds: [2]Vec2f,

    pub fn init(min: Vec2f, max: Vec2f) Bounds2f {
        return .{ .bounds = .{ min, max } };
    }
};
