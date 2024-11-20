const math = @import("math.zig");
const Vec4f = @import("vector4.zig").Vec4f;
const quaternion = @import("quaternion.zig");
const Quaternion = quaternion.Quaternion;
const Mat4x4 = @import("matrix4x4.zig").Mat4x4;

pub const Transformation = struct {
    position: Vec4f,
    scale: Vec4f,
    rotation: Quaternion,

    pub fn toMat4x4(self: Transformation) Mat4x4 {
        return Mat4x4.compose(quaternion.toMat3x3(self.rotation), self.scale, self.position);
    }

    pub fn set(self: *Transformation, other: Transformation, camera_pos: Vec4f) void {
        self.position = other.position - camera_pos;
        self.scale = other.scale;
        self.rotation = other.rotation;
    }

    pub fn transform(self: Transformation, other: Transformation) Transformation {
        return .{
            .position = self.toMat4x4().transformPoint(other.position),
            .scale = other.scale,
            .rotation = quaternion.mul(self.rotation, other.rotation),
        };
    }

    pub fn transformScaled(self: Transformation, other: Transformation) Transformation {
        return .{
            .position = self.toMat4x4().transformPoint(other.position),
            .scale = self.scale * other.scale,
            .rotation = quaternion.mul(self.rotation, other.rotation),
        };
    }

    pub fn lerp(self: Transformation, other: Transformation, t: f32) Transformation {
        const t4: Vec4f = @splat(t);

        return .{
            .position = math.lerp(self.position, other.position, t4),
            .scale = math.lerp(self.scale, other.scale, t4),
            .rotation = quaternion.slerp(self.rotation, other.rotation, t),
        };
    }
};
