const Mat3x3 = @import("matrix3x3.zig").Mat3x3;
const Vec4f = @import("vector4.zig").Vec4f;

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

    pub fn transformVector(self: Mat4x4, v: Vec4f) Vec4f {
        return Vec4f.init3(
            v.v[0] * self.m(0, 0) + v.v[1] * self.m(1, 0) + v.v[2] * self.m(2, 0),
            v.v[0] * self.m(0, 1) + v.v[1] * self.m(1, 1) + v.v[2] * self.m(2, 1),
            v.v[0] * self.m(0, 2) + v.v[1] * self.m(1, 2) + v.v[2] * self.m(2, 2),
        );
    }

    pub fn transformPoint(self: Mat4x4, v: Vec4f) Vec4f {
        return Vec4f.init3(
            v.v[0] * self.m(0, 0) + v.v[1] * self.m(1, 0) + v.v[2] * self.m(2, 0) + self.m(3, 0),
            v.v[0] * self.m(0, 1) + v.v[1] * self.m(1, 1) + v.v[2] * self.m(2, 1) + self.m(3, 1),
            v.v[0] * self.m(0, 2) + v.v[1] * self.m(1, 2) + v.v[2] * self.m(2, 2) + self.m(3, 2),
        );
    }

    pub fn affineInverted(self: Mat4x4) Mat4x4 {
        var o: Mat4x4 = undefined;

        var id: f32 = undefined;

        {
            const m00_11 = self.m(0, 0) * self.m(1, 1);
            const m01_12 = self.m(0, 1) * self.m(1, 2);
            const m02_10 = self.m(0, 2) * self.m(1, 0);
            const m00_12 = self.m(0, 0) * self.m(1, 2);
            const m01_10 = self.m(0, 1) * self.m(1, 0);
            const m02_11 = self.m(0, 2) * self.m(1, 1);

            id = 1.0 / ((m00_11 * self.m(2, 2) + m01_12 * self.m(2, 0) + m02_10 * self.m(2, 1)) -
                (m00_12 * self.m(2, 1) + m01_10 * self.m(2, 2) + m02_11 * self.m(2, 0)));

            o.r[0].v[2] = (m01_12 - m02_11) * id;
            o.r[1].v[2] = (m02_10 - m00_12) * id;
            o.r[2].v[2] = (m00_11 - m01_10) * id;
            o.r[3].v[2] = ((m00_12 * self.m(3, 1) + m01_10 * self.m(3, 2) + m02_11 * self.m(3, 0)) -
                (m00_11 * self.m(3, 2) + m01_12 * self.m(3, 0) + m02_10 * self.m(3, 1))) *
                id;
        }

        {
            const m11_22 = self.m(1, 1) * self.m(2, 2);
            const m12_21 = self.m(1, 2) * self.m(2, 1);
            const m12_20 = self.m(1, 2) * self.m(2, 0);
            const m10_22 = self.m(1, 0) * self.m(2, 2);
            const m10_21 = self.m(1, 0) * self.m(2, 1);
            const m11_20 = self.m(1, 1) * self.m(2, 0);

            o.r[0].v[0] = (m11_22 - m12_21) * id;
            o.r[1].v[0] = (m12_20 - m10_22) * id;
            o.r[2].v[0] = (m10_21 - m11_20) * id;
            o.r[3].v[0] = ((m10_22 * self.m(3, 1) + m11_20 * self.m(3, 2) + m12_21 * self.m(3, 0)) -
                (m10_21 * self.m(3, 2) + m11_22 * self.m(3, 0) + m12_20 * self.m(3, 1))) *
                id;
        }

        {
            const m02_21 = self.m(0, 2) * self.m(2, 1);
            const m01_22 = self.m(0, 1) * self.m(2, 2);
            const m00_22 = self.m(0, 0) * self.m(2, 2);
            const m02_20 = self.m(0, 2) * self.m(2, 0);
            const m01_20 = self.m(0, 1) * self.m(2, 0);
            const m00_21 = self.m(0, 0) * self.m(2, 1);

            o.r[0].v[1] = (m02_21 - m01_22) * id;
            o.r[1].v[1] = (m00_22 - m02_20) * id;
            o.r[2].v[1] = (m01_20 - m00_21) * id;
            o.r[3].v[1] = ((m00_21 * self.m(3, 2) + m01_22 * self.m(3, 0) + m02_20 * self.m(3, 1)) -
                (m00_22 * self.m(3, 1) + m01_20 * self.m(3, 2) + m02_21 * self.m(3, 0))) *
                id;
        }

        {
            o.r[0].v[3] = 0.0;
            o.r[1].v[3] = 0.0;
            o.r[2].v[3] = 0.0;
            o.r[3].v[3] = 1.0;
        }

        return o;
    }
};
