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
            .{ m00, m01, m02, 0.0 },
            .{ m10, m11, m12, 0.0 },
            .{ m20, m21, m22, 0.0 },
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

    pub fn initRotation(v: Vec4f, a: f32) Mat3x3 {
        const c = @cos(a);
        const s = @sin(a);
        const t = 1.0 - c;

        const at0 = v[0] * v[1] * t;
        const at1 = v[2] * s;

        const bt0 = v[0] * v[2] * t;
        const bt1 = v[1] * s;

        const ct0 = v[1] * v[2] * t;
        const ct1 = v[0] * s;

        return init9(
            c + v[0] * v[1] * t,
            at0 - at1,
            bt0 + bt1,

            at0 + at1,
            c + v[1] * v[1] * t,
            ct0 - ct1,

            bt0 - bt1,
            ct0 + ct1,
            c + v[2] * v[2] * t,
        );
    }

    pub fn mul(a: Mat3x3, b: Mat3x3) Mat3x3 {
        return init9(
            a.r[0][0] * b.r[0][0] + a.r[0][1] * b.r[1][0] + a.r[0][2] * b.r[2][0],
            a.r[0][0] * b.r[0][1] + a.r[0][1] * b.r[1][1] + a.r[0][2] * b.r[2][1],
            a.r[0][0] * b.r[0][2] + a.r[0][1] * b.r[1][2] + a.r[0][2] * b.r[2][2],
            a.r[1][0] * b.r[0][0] + a.r[1][1] * b.r[1][0] + a.r[1][2] * b.r[2][0],
            a.r[1][0] * b.r[0][1] + a.r[1][1] * b.r[1][1] + a.r[1][2] * b.r[2][1],
            a.r[1][0] * b.r[0][2] + a.r[1][1] * b.r[1][2] + a.r[1][2] * b.r[2][2],
            a.r[2][0] * b.r[0][0] + a.r[2][1] * b.r[1][0] + a.r[2][2] * b.r[2][0],
            a.r[2][0] * b.r[0][1] + a.r[2][1] * b.r[1][1] + a.r[2][2] * b.r[2][1],
            a.r[2][0] * b.r[0][2] + a.r[2][1] * b.r[1][2] + a.r[2][2] * b.r[2][2],
        );
    }

    pub inline fn transformVector(self: Mat3x3, v: Vec4f) Vec4f {
        // return .{
        //     v[0] * self.m(0, 0) + v[1] * self.m(1, 0) + v[2] * self.m(2, 0),
        //     v[0] * self.m(0, 1) + v[1] * self.m(1, 1) + v[2] * self.m(2, 1),
        //     v[0] * self.m(0, 2) + v[1] * self.m(1, 2) + v[2] * self.m(2, 2),
        //     0.0,
        // };

        var result = @splat(4, v[0]); // @shuffle(f32, v, v, [4]i32{ 0, 0, 0, 0 });
        result = result * self.r[0];
        var temp = @splat(4, v[1]); // @shuffle(f32, v, v, [4]i32{ 1, 1, 1, 1 });
        temp = temp * self.r[1];
        result = result + temp;
        temp = @splat(4, v[2]); // @shuffle(f32, v, v, [4]i32{ 2, 2, 2, 2 });
        temp = temp * self.r[2];
        return result + temp;
    }

    pub inline fn transformVectorTransposed(self: Mat3x3, v: Vec4f) Vec4f {
        const x = v * self.r[0];
        const y = v * self.r[1];
        const z = v * self.r[2];

        return .{
            x[0] + x[1] + x[2],
            y[0] + y[1] + y[2],
            z[0] + z[1] + z[2],
            0.0,
        };
    }
};

pub const Mat2x3 = struct {
    r: [2]Vec4f,

    pub fn init6(
        m00: f32,
        m01: f32,
        m02: f32,
        m10: f32,
        m11: f32,
        m12: f32,
    ) Mat2x3 {
        return .{ .r = [2]Vec4f{
            .{ m00, m01, m02, 0.0 },
            .{ m10, m11, m12, 0.0 },
        } };
    }

    pub fn initRotation(v: Vec4f, a: f32) Mat2x3 {
        const c = @cos(a);
        const s = @sin(a);
        const t = 1.0 - c;

        const at0 = v[0] * v[1] * t;
        const at1 = v[2] * s;

        const bt0 = v[0] * v[2] * t;
        const bt1 = v[1] * s;

        const ct0 = v[1] * v[2] * t;
        const ct1 = v[0] * s;

        return init6(
            c + v[0] * v[1] * t,
            at0 - at1,
            bt0 + bt1,

            at0 + at1,
            c + v[1] * v[1] * t,
            ct0 - ct1,
        );
    }

    pub inline fn transformVector(self: Mat2x3, v: Vec4f) Vec4f {
        // return .{
        //     v[0] * self.m(0, 0) + v[1] * self.m(1, 0),
        //     v[0] * self.m(0, 1) + v[1] * self.m(1, 1),
        //     v[0] * self.m(0, 2) + v[1] * self.m(1, 2),
        //     0.0,
        // };

        var result = @splat(4, v[0]); // @shuffle(f32, v, v, [4]i32{ 0, 0, 0, 0 });
        result = result * self.r[0];
        var temp = @splat(4, v[1]); // @shuffle(f32, v, v, [4]i32{ 1, 1, 1, 1 });
        temp = temp * self.r[1];
        return result + temp;
    }
};
