const Float4 = @import("../../../image/image.zig").Float4;

pub const Base = struct {
    source: *const Float4 = undefined,
    destination: *Float4 = undefined,

    exposure_factor: f32 = 1.0,
};
