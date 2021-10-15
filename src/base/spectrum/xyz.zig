const Vec4f = @import("../math/vector4.zig").Vec4f;

pub fn XYZ_to_sRGB(xyz: Vec4f) Vec4f {
    return .{
        3.240970 * xyz[0] - 1.537383 * xyz[1] - 0.498611 * xyz[2],
        -0.969244 * xyz[0] + 1.875968 * xyz[1] + 0.041555 * xyz[2],
        0.055630 * xyz[0] - 0.203977 * xyz[1] + 1.056972 * xyz[2],
        0.0,
    };
}
