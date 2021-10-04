const Vec4f = @import("vector4.zig").Vec4f;
const quaternion = @import("quaternion.zig");
const Quaternion = quaternion.Quaternion;
const Mat4x4 = @import("matrix4x4.zig").Mat4x4;

pub const Transformation = struct {
    position: Vec4f = undefined,
    scale: Vec4f = undefined,
    rotation: Quaternion = undefined,

    pub fn toMat4x4(self: Transformation) Mat4x4 {
        return Mat4x4.compose(quaternion.toMat3x3(self.rotation), self.scale, self.position);
    }

    pub fn transform(self: Transformation, other: Transformation) Transformation {
        return .{
            .position = self.toMat4x4().transformPoint(other.position),
            .scale = other.scale,
            .rotation = quaternion.mul(self.rotation, other.rotation),
        };
    }

    pub fn lerp(self: Transformation, other: Transformation, t: f32) Transformation {
        return .{
            .postion = math.lerp3(self.postion, other.position, t),
            .rotation = math.lerp3(self.position, other.position, t),
            .rotation = quaternion.slerp(self.rotation, other.rotation, t),
        };
    }
};
