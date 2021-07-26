const base = @import("../../base/base.zig");
usingnamespace base.math;

pub const Camera_sample = struct {
    pixel: Vec2i,
    pixel_uv: Vec2f,
};
