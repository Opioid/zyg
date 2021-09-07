const Float4 = @import("../../../image/image.zig").Float4;

const std = @import("std");

pub const Base = struct {
    source: *const Float4 = undefined,
    destination: *Float4 = undefined,

    exposure_factor: f32,

    pub fn init(exposure: f32) Base {
        return .{ .exposure_factor = std.math.exp2(exposure) };
    }
};
