const Vec4f = @import("vector4.zig").Vec4f;

pub const Mat3x3 = struct {
    r: [3]Vec4f,

    pub fn init9(
        m00: f32,
        m01: f32,
        m02: f32,
        m10: f32,
        m11: f32,
        m12: f32,
        m20: f32,
        m21: f32,
        m22: f32,
    ) Mat3x3 {
        return .{ .r = [3]Vec4f{
            Vec4f.init3(m00, m01, m02),
            Vec4f.init3(m10, m11, m12),
            Vec4f.init3(m20, m21, m22),
        } };
    }

    pub fn init3(x: Vec4f, y: Vec4f, z: Vec4f) Mat3x3 {
        return .{ .r = [3]Vec4f{ x, y, z } };
    }

    pub fn initRotationX(a: f32) Mat3x3 {
        const c = @cos(a);
        const s = @sin(a);

        return init9(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
    }

    pub fn initRotationY(a: f32) Mat3x3 {
        const c = @cos(a);
        const s = @sin(a);

        return init9(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
    }

    pub fn initRotationZ(a: f32) Mat3x3 {
        const c = @cos(a);
        const s = @sin(a);

        return init9(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
    }

    pub fn m(self: Mat3x3, y: u32, x: u32) f32 {
        return self.r[y].v[x];
    }

    pub fn setElem(self: *Mat3x3, y: u32, x: u32, s: f32) void {
        self.r[y].v[x] = s;
    }

    pub fn mul(a: Mat3x3, b: Mat3x3) Mat3x3 {
        return init9(
            a.m(0, 0) * b.m(0, 0) + a.m(0, 1) * b.m(1, 0) + a.m(0, 2) * b.m(2, 0),
            a.m(0, 0) * b.m(0, 1) + a.m(0, 1) * b.m(1, 1) + a.m(0, 2) * b.m(2, 1),
            a.m(0, 0) * b.m(0, 2) + a.m(0, 1) * b.m(1, 2) + a.m(0, 2) * b.m(2, 2),
            a.m(1, 0) * b.m(0, 0) + a.m(1, 1) * b.m(1, 0) + a.m(1, 2) * b.m(2, 0),
            a.m(1, 0) * b.m(0, 1) + a.m(1, 1) * b.m(1, 1) + a.m(1, 2) * b.m(2, 1),
            a.m(1, 0) * b.m(0, 2) + a.m(1, 1) * b.m(1, 2) + a.m(1, 2) * b.m(2, 2),
            a.m(2, 0) * b.m(0, 0) + a.m(2, 1) * b.m(1, 0) + a.m(2, 2) * b.m(2, 0),
            a.m(2, 0) * b.m(0, 1) + a.m(2, 1) * b.m(1, 1) + a.m(2, 2) * b.m(2, 1),
            a.m(2, 0) * b.m(0, 2) + a.m(2, 1) * b.m(1, 2) + a.m(2, 2) * b.m(2, 2),
        );
    }

    pub fn transformVector(self: Mat3x3, v: Vec4f) Vec4f {
        return Vec4f.init3(
            v.v[0] * self.m(0, 0) + v.v[1] * self.m(1, 0) + v.v[2] * self.m(2, 0),
            v.v[0] * self.m(0, 1) + v.v[1] * self.m(1, 1) + v.v[2] * self.m(2, 1),
            v.v[0] * self.m(0, 2) + v.v[1] * self.m(1, 2) + v.v[2] * self.m(2, 2),
        );
    }

    pub fn transformVectorTransposed(self: Mat3x3, v: Vec4f) Vec4f {
        return Vec4f.init3(
            v.v[0] * self.m(0, 0) + v.v[1] * self.m(0, 1) + v.v[2] * self.m(0, 2),
            v.v[0] * self.m(1, 0) + v.v[1] * self.m(1, 1) + v.v[2] * self.m(1, 2),
            v.v[0] * self.m(2, 0) + v.v[1] * self.m(2, 1) + v.v[2] * self.m(2, 2),
        );
    }
};
