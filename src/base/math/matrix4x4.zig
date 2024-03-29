const Mat3x3 = @import("matrix3x3.zig").Mat3x3;
const math = @import("vector4.zig");
const Vec4f = math.Vec4f;

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
        return .{ .r = .{
            .{ m00, m01, m02, m03 },
            .{ m10, m11, m12, m13 },
            .{ m20, m21, m22, m23 },
            .{ m30, m31, m32, m33 },
        } };
    }

    pub fn initArray(ma: [16]f32) Mat4x4 {
        return .{ .r = .{
            .{ ma[0], ma[1], ma[2], ma[3] },
            .{ ma[4], ma[5], ma[6], ma[7] },
            .{ ma[8], ma[9], ma[10], ma[11] },
            .{ ma[12], ma[13], ma[14], ma[15] },
        } };
    }

    pub fn initMat3x3(basis: Mat3x3) Mat4x4 {
        return init16(
            basis.r[0][0],
            basis.r[0][1],
            basis.r[0][2],
            0.0,
            basis.r[1][0],
            basis.r[1][1],
            basis.r[1][2],
            0.0,
            basis.r[2][0],
            basis.r[2][1],
            basis.r[2][2],
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
        );
    }

    pub fn initLookAt(pos: Vec4f, dir: Vec4f, up: Vec4f) Mat4x4 {
        const right = math.normalize3(math.cross3(up, dir));
        const new_up = math.cross3(dir, right);

        return init16(
            right[0],
            right[1],
            right[2],
            0.0,
            new_up[0],
            new_up[1],
            new_up[2],
            0.0,
            dir[0],
            dir[1],
            dir[2],
            0.0,
            pos[0],
            pos[1],
            pos[2],
            1.0,
        );
    }

    pub fn compose(basis: Mat3x3, scale: Vec4f, origin: Vec4f) Mat4x4 {
        return init16(
            basis.r[0][0] * scale[0],
            basis.r[0][1] * scale[0],
            basis.r[0][2] * scale[0],
            0.0,
            basis.r[1][0] * scale[1],
            basis.r[1][1] * scale[1],
            basis.r[1][2] * scale[1],
            0.0,
            basis.r[2][0] * scale[2],
            basis.r[2][1] * scale[2],
            basis.r[2][2] * scale[2],
            0.0,
            origin[0],
            origin[1],
            origin[2],
            1.0,
        );
    }

    pub fn decompose(self: Mat4x4, basis: *Mat3x3, scale: *Vec4f, origin: *Vec4f) void {
        const mx = self.x();
        const my = self.y();
        const mz = self.z();

        const sx = math.length3(mx);
        const sy = math.length3(my);
        const sz = math.length3(mz);

        basis.* = Mat3x3.init3(mx / @as(Vec4f, @splat(sx)), my / @as(Vec4f, @splat(sy)), mz / @as(Vec4f, @splat(sz)));
        scale.* = Vec4f{ sx, sy, sz, 0.0 };
        origin.* = self.w();
    }

    pub fn m(self: Mat4x4, cy: u32, cx: u32) f32 {
        return self.r[cy][cx];
    }

    pub fn x(self: Mat4x4) Vec4f {
        return self.r[0];
    }

    pub fn y(self: Mat4x4) Vec4f {
        return self.r[1];
    }

    pub fn z(self: Mat4x4) Vec4f {
        return self.r[2];
    }

    pub fn w(self: Mat4x4) Vec4f {
        return self.r[3];
    }

    pub fn transformVector(self: Mat4x4, v: Vec4f) Vec4f {
        // return .{
        //     v[0] * self.m(0, 0) + v[1] * self.m(1, 0) + v[2] * self.m(2, 0),
        //     v[0] * self.m(0, 1) + v[1] * self.m(1, 1) + v[2] * self.m(2, 1),
        //     v[0] * self.m(0, 2) + v[1] * self.m(1, 2) + v[2] * self.m(2, 2),
        //     0.0,
        // };

        var result: Vec4f = @splat(v[0]); // @shuffle(f32, v, v, [4]i32{ 0, 0, 0, 0 });
        result = result * self.r[0];
        var temp: Vec4f = @splat(v[1]); // @shuffle(f32, v, v, [4]i32{ 1, 1, 1, 1 });
        temp = temp * self.r[1];
        result = result + temp;
        temp = @splat(v[2]); // @shuffle(f32, v, v, [4]i32{ 2, 2, 2, 2 });
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

        var result: Vec4f = @splat(v[0]); // @shuffle(f32, v, v, [4]i32{ 0, 0, 0, 0 });
        result = result * self.r[0];
        var temp: Vec4f = @splat(v[1]); // @shuffle(f32, v, v, [4]i32{ 1, 1, 1, 1 });
        temp = temp * self.r[1];
        result = result + temp;
        temp = @splat(v[2]); // @shuffle(f32, v, v, [4]i32{ 2, 2, 2, 2 });
        temp = temp * self.r[2];
        result = result + temp;
        return result + self.r[3];
    }

    pub inline fn transformVectorTransposed(self: Mat4x4, v: Vec4f) Vec4f {
        const vx = v * self.r[0];
        const vy = v * self.r[1];
        const vz = v * self.r[2];

        return .{
            vx[0] + vx[1] + vx[2],
            vy[0] + vy[1] + vy[2],
            vz[0] + vz[1] + vz[2],
            0.0,
        };
    }

    pub fn transformPointTransposed(self: Mat4x4, p: Vec4f) Vec4f {
        return self.transformVectorTransposed(p - self.r[3]);
    }

    pub fn affineInverted(self: Mat4x4) Mat4x4 {
        var o: Mat4x4 = undefined;

        const m00_11 = self.m(0, 0) * self.m(1, 1);
        const m01_12 = self.m(0, 1) * self.m(1, 2);
        const m02_10 = self.m(0, 2) * self.m(1, 0);
        const m00_12 = self.m(0, 0) * self.m(1, 2);
        const m01_10 = self.m(0, 1) * self.m(1, 0);
        const m02_11 = self.m(0, 2) * self.m(1, 1);

        const id = 1.0 / ((m00_11 * self.m(2, 2) + m01_12 * self.m(2, 0) + m02_10 * self.m(2, 1)) -
            (m00_12 * self.m(2, 1) + m01_10 * self.m(2, 2) + m02_11 * self.m(2, 0)));

        o.r[0][2] = (m01_12 - m02_11) * id;
        o.r[1][2] = (m02_10 - m00_12) * id;
        o.r[2][2] = (m00_11 - m01_10) * id;
        o.r[3][2] = ((m00_12 * self.m(3, 1) + m01_10 * self.m(3, 2) + m02_11 * self.m(3, 0)) -
            (m00_11 * self.m(3, 2) + m01_12 * self.m(3, 0) + m02_10 * self.m(3, 1))) *
            id;

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

        o.r[0][3] = 0.0;
        o.r[1][3] = 0.0;
        o.r[2][3] = 0.0;
        o.r[3][3] = 1.0;

        return o;
    }
};
