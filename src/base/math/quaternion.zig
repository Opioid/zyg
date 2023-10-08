const math = @import("vector4.zig");
const Vec4f = math.Vec4f;
const Mat3x3 = @import("matrix3x3.zig").Mat3x3;

const std = @import("std");

pub const Quaternion = Vec4f;

pub const identity = Quaternion{ 0.0, 0.0, 0.0, 1.0 };

pub fn initFromMat3x3(m: Mat3x3) Quaternion {
    var t: f32 = undefined;
    var q: Quaternion = undefined;

    if (m.r[2][2] < 0.0) {
        if (m.r[0][0] > m.r[1][1]) {
            t = 1.0 + m.r[0][0] - m.r[1][1] - m.r[2][2];
            q = .{ t, m.r[0][1] + m.r[1][0], m.r[2][0] + m.r[0][2], m.r[2][1] - m.r[1][2] };
        } else {
            t = 1.0 - m.r[0][0] + m.r[1][1] - m.r[2][2];
            q = .{ m.r[0][1] + m.r[1][0], t, m.r[1][2] + m.r[2][1], m.r[0][2] - m.r[2][0] };
        }
    } else {
        if (m.r[0][0] < -m.r[1][1]) {
            t = 1.0 - m.r[0][0] - m.r[1][1] + m.r[2][2];
            q = .{ m.r[2][0] + m.r[0][2], m.r[1][2] + m.r[2][1], t, m.r[1][0] - m.r[0][1] };
        } else {
            t = 1.0 + m.r[0][0] + m.r[1][1] + m.r[2][2];
            q = .{ m.r[2][1] - m.r[1][2], m.r[0][2] - m.r[2][0], m.r[1][0] - m.r[0][1], t };
        }
    }

    return q * @as(Vec4f, @splat(0.5 / @sqrt(t)));
}

pub fn initFromTN(t: Vec4f, n: Vec4f) Quaternion {
    const b = math.cross3(n, t);

    const tbn = Mat3x3.init3(t, b, n);

    var q = initFromMat3x3(tbn);

    const threshold = 0.000001;
    const renormalization = comptime @sqrt(1.0 - threshold * threshold);

    if (@abs(q[3]) < threshold) {
        q[0] *= renormalization;
        q[1] *= renormalization;
        q[2] *= renormalization;
        q[3] = if (q[3] < 0.0) -threshold else threshold;
    }

    if (q[3] < 0.0) {
        q = -q;
    }

    return q;
}

pub fn initRotationX(a: f32) Quaternion {
    return .{ @sin(a * 0.5), 0.0, 0.0, @cos(a * 0.5) };
}

pub inline fn toMat3x3(q: Quaternion) Mat3x3 {
    //     void quat_to_mat33_ndr(mat33_t* m, quat_t* q)
    // {
    //   float x  = q->x, y  = q->y, z  = q->z, w  = q->w;
    //   float tx = 2*x,  ty = 2*y,  tz = 2*z;
    //   float xy = ty*x, xz = tz*x, yz = ty*z;
    //   float wx = tx*w, wy = ty*w, wz = tz*w;

    //   // diagonal terms
    //   float t0 = (w+y)*(w-y), t1 = (x+z)*(x-z);
    //   float t2 = (w+x)*(w-x), t3 = (y+z)*(y-z);
    //   m->m00 = t0+t1;
    //   m->m11 = t2+t3;
    //   m->m22 = t2-t3;

    //   m->m10 = xy+wz; m->m01 = xy-wz;
    //   m->m20 = xz-wy; m->m02 = xz+wy;
    //   m->m21 = yz+wx; m->m12 = yz-wx;
    // }

    const tq = q + q;

    const xy = tq[1] * q[0];
    const xz = tq[2] * q[0];
    const yz = tq[1] * q[2];

    const w = tq * @as(Vec4f, @splat(q[3]));

    // diagonal terms
    const a = @shuffle(f32, q, q, [4]i32{ 3, 0, 3, 1 });
    const b = @shuffle(f32, q, q, [4]i32{ 1, 2, 0, 2 });
    const t = (a + b) * (a - b);

    return Mat3x3.init9(
        t[0] + t[1],
        xy - w[2],
        xz + w[1],
        xy + w[2],
        t[2] + t[3],
        yz - w[0],
        xz - w[1],
        yz + w[0],
        t[2] - t[3],
    );
}

pub inline fn toTN(q: Quaternion) [2]Vec4f {
    //     void quat_to_mat33_ndr(mat33_t* m, quat_t* q)
    // {
    //   float x  = q->x, y  = q->y, z  = q->z, w  = q->w;
    //   float tx = 2*x,  ty = 2*y,  tz = 2*z;
    //   float xy = ty*x, xz = tz*x, yz = ty*z;
    //   float wx = tx*w, wy = ty*w, wz = tz*w;

    //   // diagonal terms
    //   float t0 = (w+y)*(w-y), t1 = (x+z)*(x-z);
    //   float t2 = (w+x)*(w-x), t3 = (y+z)*(y-z);
    //   m->m00 = t0+t1;
    //   m->m11 = t2+t3;
    //   m->m22 = t2-t3;

    //   m->m10 = xy+wz; m->m01 = xy-wz;
    //   m->m20 = xz-wy; m->m02 = xz+wy;
    //   m->m21 = yz+wx; m->m12 = yz-wx;
    // }

    const tq = q + q;

    const xy = tq[1] * q[0];
    const xz = tq[2] * q[0];
    const yz = tq[1] * q[2];

    const w = tq * @as(Vec4f, @splat(q[3]));

    // diagonal terms
    const a = @shuffle(f32, q, q, [4]i32{ 3, 0, 3, 1 });
    const b = @shuffle(f32, q, q, [4]i32{ 1, 2, 0, 2 });
    const t = (a + b) * (a - b);

    return .{ .{ t[0] + t[1], xy - w[2], xz + w[1], 0.0 }, .{ xz - w[1], yz + w[0], t[2] - t[3], 0.0 } };
}

pub inline fn toNormal(q: Quaternion) Vec4f {
    //     void quat_to_mat33_ndr(mat33_t* m, quat_t* q)
    // {
    //   float x  = q->x, y  = q->y, z  = q->z, w  = q->w;
    //   float tx = 2*x,  ty = 2*y,  tz = 2*z;
    //   float xy = ty*x, xz = tz*x, yz = ty*z;
    //   float wx = tx*w, wy = ty*w, wz = tz*w;

    //   // diagonal terms
    //   float t0 = (w+y)*(w-y), t1 = (x+z)*(x-z);
    //   float t2 = (w+x)*(w-x), t3 = (y+z)*(y-z);
    //   m->m00 = t0+t1;
    //   m->m11 = t2+t3;
    //   m->m22 = t2-t3;

    //   m->m10 = xy+wz; m->m01 = xy-wz;
    //   m->m20 = xz-wy; m->m02 = xz+wy;
    //   m->m21 = yz+wx; m->m12 = yz-wx;
    // }

    const tq = q + q;

    const xz = tq[2] * q[0];
    const yz = tq[1] * q[2];

    const w = tq * @as(Vec4f, @splat(q[3]));

    // diagonal terms
    const a = @shuffle(f32, q, q, [4]i32{ 3, 0, 3, 1 });
    const b = @shuffle(f32, q, q, [4]i32{ 1, 2, 0, 2 });
    const t = (a + b) * (a - b);

    return .{ xz - w[1], yz + w[0], t[2] - t[3], 0.0 };
}

pub inline fn mul(a: Quaternion, b: Quaternion) Quaternion {
    return .{
        (a[3] * b[0] + a[0] * b[3]) + (a[1] * b[2] - a[2] * b[1]),
        (a[3] * b[1] + a[1] * b[3]) + (a[2] * b[0] - a[0] * b[2]),
        (a[3] * b[2] + a[2] * b[3]) + (a[0] * b[1] - a[1] * b[0]),
        (a[3] * b[3] - a[0] * b[0]) - (a[1] * b[1] + a[2] * b[2]),
    };
}

pub inline fn slerp(a: Quaternion, b: Quaternion, t: f32) Quaternion {
    const ab = a * b;
    var cosom = ab[0] + ab[1] + ab[2] + ab[3];
    var end = b;

    // adjust signs (if necessary)
    if (cosom < 0.0) {
        cosom = -cosom;
        end = -end;
    }

    var sclp: f32 = undefined;
    var sclq: f32 = undefined;

    if (1.0 - cosom > 0.00001) {
        // Standard case (slerp)
        const omega = std.math.acos(cosom);
        const sinom = @sin(omega);

        sclp = @sin((1.0 - t) * omega) / sinom;
        sclq = @sin(t * omega) / sinom;
    } else {
        // Very close, do linear interpolation to avoid division by sinom=0
        sclp = 1.0 - t;
        sclq = t;
    }

    return @as(Vec4f, @splat(sclp)) * a + @as(Vec4f, @splat(sclq)) * end;
}
