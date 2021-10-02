const Vec4f = @import("vector4.zig").Vec4f;
const quaternion = @import("quaternion.zig");
const Quaternion = quaternion.Quaternion;
const Mat4x4 = @import("matrix4x4.zig").Mat4x4;

pub const Transformation = struct {
    position: Vec4f,
    scale: Vec4f,
    rotation: Quaternion,

    pub fn toMat4x4(self: Transformation) Mat4x4 {
        return Mat4x4.compose(self.rotation.initMat3x3(), self.scale, self.position);
    }

    pub fn transform(self: Transformation, other: Transformation) Transformation {
        return .{
            .position = self.toMat4x4().transformPoint(other.position),
            .scale = other.scale,
            .rotation = quaternion.mul(other.rotation, self.rotation),
        };
    }
};
