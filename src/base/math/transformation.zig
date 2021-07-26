const Vec4f = @import("vector4.zig").Vec4f;
const Quaternion = @import("quaternion.zig").Quaternion;

pub const Transformation = struct {
    position: Vec4f,
    scale: Vec4f,
    rotation: Quaternion,
};
