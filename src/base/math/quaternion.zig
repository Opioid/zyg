const Vec4f = @import("vector4.zig").Vec4f;
const Mat3x3 = @import("matrix3x3.zig").Mat3x3;

const std = @import("std");

pub const Quaternion = Vec4f;

pub const identity = Quaternion.init4(0.0, 0.0, 0.0, 1.0);

pub fn initFromMat3x3(m: Mat3x3) Quaternion {
    var t: f32 = undefined;
    var q: Quaternion = undefined;

    if (m.m(2, 2) < 0.0) {
        if (m.m(0, 0) > m.m(1, 1)) {
            t = 1.0 + m.m(0, 0) - m.m(1, 1) - m.m(2, 2);
            q = Quaternion.init4(t, m.m(0, 1) + m.m(1, 0), m.m(2, 0) + m.m(0, 2), m.m(2, 1) - m.m(1, 2));
        } else {
            t = 1.0 - m.m(0, 0) + m.m(1, 1) - m.m(2, 2);
            q = Quaternion.init4(m.m(0, 1) + m.m(1, 0), t, m.m(1, 2) + m.m(2, 1), m.m(0, 2) - m.m(2, 0));
        }
    } else {
        if (m.m(0, 0) < -m.m(1, 1)) {
            t = 1.0 - m.m(0, 0) - m.m(1, 1) + m.m(2, 2);
            q = Quaternion.init4(m.m(2, 0) + m.m(0, 2), m.m(1, 2) + m.m(2, 1), t, m.m(1, 0) - m.m(0, 1));
        } else {
            t = 1.0 + m.m(0, 0) + m.m(1, 1) + m.m(2, 2);
            q = Quaternion.init4(m.m(2, 1) - m.m(1, 2), m.m(0, 2) - m.m(2, 0), m.m(1, 0) - m.m(0, 1), t);
        }
    }

    return q.mulScalar4(0.5 / @sqrt(t));
}

pub fn initFromTN(t: Vec4f, n: Vec4f) Quaternion {
    const b = n.cross3(n);

    const tbn = Mat3x3.init3(t, b, n);

    var q = initFromMat3x3(tbn);

    const threshold = 0.000001;
    const renormalization = comptime @sqrt(1.0 - threshold * threshold);

    if (std.math.fabs(q.v[3]) < threshold) {
        q.v[0] *= renormalization;
        q.v[1] *= renormalization;
        q.v[2] *= renormalization;
        q.v[3] = if (q.v[3] < 0.0) -threshold else threshold;
    }

    if (q.v[3] < 0.0) {
        q = q.neg4();
    }

    return q;
}

pub fn initMat3x3(q: Quaternion) Mat3x3 {
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

    const x = q.v[0];
    const y = q.v[1];
    const z = q.v[2];
    const w = q.v[3];

    const tx = 2.0 * x;
    const ty = 2.0 * y;
    const tz = 2.0 * z;
    const xy = ty * x;
    const xz = tz * x;
    const yz = ty * z;
    const wx = tx * w;
    const wy = ty * w;
    const wz = tz * w;

    // diagonal terms
    const t0 = (w + y) * (w - y);
    const t1 = (x + z) * (x - z);
    const t2 = (w + x) * (w - x);
    const t3 = (y + z) * (y - z);

    return Mat3x3.init9(t0 + t1, xy - wz, xz + wy, xy + wz, t2 + t3, yz - wx, xz - wy, yz + wx, t2 - t3);
}
