usingnamespace @import("matrix3x3.zig");
usingnamespace @import("vector4.zig");

pub const Mat4x4 = struct {
    r: [4]Vec4f,

    pub fn init16(
        m00: f32,
        m01: f32,
        m02: f32,
        m03: f32,
        m10: f32,
        m11: f32,
        m12: f32,
        m13: f32,
        m20: f32,
        m21: f32,
        m22: f32,
        m23: f32,
        m30: f32,
        m31: f32,
        m32: f32,
        m33: f32,
    ) Mat4x4 {
        return .{ .r = [4]Vec4f{
            Vec4f.init4(m00, m01, m02, m03),
            Vec4f.init4(m10, m11, m12, m13),
            Vec4f.init4(m20, m21, m22, m23),
            Vec4f.init4(m30, m31, m32, m33),
        } };
    }

    pub fn compose(basis: Mat3x3, scale: Vec4f, origin: Vec4f) Mat4x4 {
        return init16(
            basis.m(0, 0) * scale.v[0],
            basis.m(0, 1) * scale.v[0],
            basis.m(0, 2) * scale.v[0],
            0.0,
            basis.m(1, 0) * scale.v[1],
            basis.m(1, 1) * scale.v[1],
            basis.m(1, 2) * scale.v[1],
            0.0,
            basis.m(2, 0) * scale.v[2],
            basis.m(2, 1) * scale.v[2],
            basis.m(2, 2) * scale.v[2],
            0.0,
            origin.v[0],
            origin.v[1],
            origin.v[2],
            1.0,
        );
    }

    pub fn m(self: Mat4x4, y: u32, x: u32) f32 {
        return self.r[y].v[x];
    }

    pub fn setElem(self: *Mat4x4, y: u32, x: u32, s: f32) void {
        self.r[y].v[x] = s;
    }
};
