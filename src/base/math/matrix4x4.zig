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
            .{ m00, m01, m02, m03 },
            .{ m10, m11, m12, m13 },
            .{ m20, m21, m22, m23 },
            .{ m30, m31, m32, m33 },
        } };
    }

    pub fn compose(basis: Mat3x3, scale: Vec4f, origin: Vec4f) Mat4x4 {
        return init16(
            basis.m(0, 0) * scale[0],
            basis.m(0, 1) * scale[0],
            basis.m(0, 2) * scale[0],
            0.0,
            basis.m(1, 0) * scale[1],
            basis.m(1, 1) * scale[1],
            basis.m(1, 2) * scale[1],
            0.0,
            basis.m(2, 0) * scale[2],
            basis.m(2, 1) * scale[2],
            basis.m(2, 2) * scale[2],
            0.0,
            origin[0],
            origin[1],
            origin[2],
            1.0,
        );
    }

    pub fn m(self: Mat4x4, y: u32, x: u32) f32 {
        return self.r[y][x];
    }

    pub fn setElem(self: *Mat4x4, y: u32, x: u32, s: f32) void {
        self.r[y][x] = s;
    }

    pub fn transformVector(self: Mat4x4, v: Vec4f) Vec4f {
        // return .{
        //     v[0] * self.m(0, 0) + v[1] * self.m(1, 0) + v[2] * self.m(2, 0),
        //     v[0] * self.m(0, 1) + v[1] * self.m(1, 1) + v[2] * self.m(2, 1),
        //     v[0] * self.m(0, 2) + v[1] * self.m(1, 2) + v[2] * self.m(2, 2),
        //     0.0,
        // };

        var result = @shuffle(f32, v, v, [4]i32{ 0, 0, 0, 0 });
        result = result * self.r[0];
        var temp = @shuffle(f32, v, v, [4]i32{ 1, 1, 1, 1 });
        temp = temp * self.r[1];
        result = result + temp;
        temp = @shuffle(f32, v, v, [4]i32{ 2, 2, 2, 2 });
        temp = temp * self.r[2];
        return result + temp;
    }

    pub fn transformPoint(self: Mat4x4, v: Vec4f) Vec4f {
        // return .{
        //     v[0] * self.m(0, 0) + v[1] * self.m(1, 0) + v[2] * self.m(2, 0) + self.m(3, 0),
        //     v[0] * self.m(0, 1) + v[1] * self.m(1, 1) + v[2] * self.m(2, 1) + self.m(3, 1),
        //     v[0] * self.m(0, 2) + v[1] * self.m(1, 2) + v[2] * self.m(2, 2) + self.m(3, 2),
        //     0.0,
        // };

        var result = @shuffle(f32, v, v, [4]i32{ 0, 0, 0, 0 });
        result = result * self.r[0];
        var temp = @shuffle(f32, v, v, [4]i32{ 1, 1, 1, 1 });
        temp = temp * self.r[1];
        result = result + temp;
        temp = @shuffle(f32, v, v, [4]i32{ 2, 2, 2, 2 });
        temp = temp * self.r[2];
        result = result + temp;
        return result + self.r[3];
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

            o.r[0][2] = (m01_12 - m02_11) * id;
            o.r[1][2] = (m02_10 - m00_12) * id;
            o.r[2][2] = (m00_11 - m01_10) * id;
            o.r[3][2] = ((m00_12 * self.m(3, 1) + m01_10 * self.m(3, 2) + m02_11 * self.m(3, 0)) -
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

            o.r[0][0] = (m11_22 - m12_21) * id;
            o.r[1][0] = (m12_20 - m10_22) * id;
            o.r[2][0] = (m10_21 - m11_20) * id;
            o.r[3][0] = ((m10_22 * self.m(3, 1) + m11_20 * self.m(3, 2) + m12_21 * self.m(3, 0)) -
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

            o.r[0][1] = (m02_21 - m01_22) * id;
            o.r[1][1] = (m00_22 - m02_20) * id;
            o.r[2][1] = (m01_20 - m00_21) * id;
            o.r[3][1] = ((m00_21 * self.m(3, 2) + m01_22 * self.m(3, 0) + m02_20 * self.m(3, 1)) -
                (m00_22 * self.m(3, 1) + m01_20 * self.m(3, 2) + m02_21 * self.m(3, 0))) *
                id;
        }

        {
            o.r[0][3] = 0.0;
            o.r[1][3] = 0.0;
            o.r[2][3] = 0.0;
            o.r[3][3] = 1.0;
        }

        return o;
    }
};
