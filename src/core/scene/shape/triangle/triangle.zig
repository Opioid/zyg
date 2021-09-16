const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const IndexTriangle = struct {
    i: [3]u32,
    part: u32,
};

pub fn min(a: Vec4f, b: Vec4f, c: Vec4f) Vec4f {
    return math.min(a, math.min(b, c));
}

pub fn max(a: Vec4f, b: Vec4f, c: Vec4f) Vec4f {
    return math.max(a, math.max(b, c));
}

pub fn intersect(ray: *Ray, a: Vec4f, b: Vec4f, c: Vec4f, u_out: *f32, v_out: *f32) bool {
    const e1 = b - a;
    const e2 = c - a;

    const tvec = ray.origin - a;
    const pvec = math.cross3(ray.direction, e2);
    const qvec = math.cross3(tvec, e1);

    const e1_d_pv = math.dot3(e1, pvec);
    const tv_d_pv = math.dot3(tvec, pvec);
    const di_d_qv = math.dot3(ray.direction, qvec);
    const e2_d_qv = math.dot3(e2, qvec);

    const inv_det = 1.0 / e1_d_pv;

    const u = tv_d_pv * inv_det;
    const v = di_d_qv * inv_det;
    const hit_t = e2_d_qv * inv_det;

    const uv = u + v;

    if (u >= 0.0 and 1.0 >= u and v >= 0.0 and 1.0 >= uv and hit_t >= ray.minT() and ray.maxT() >= hit_t) {
        ray.setMaxT(hit_t);
        u_out.* = u;
        v_out.* = v;
        return true;
    }

    return false;
}

pub fn intersectP(ray: Ray, a: Vec4f, b: Vec4f, c: Vec4f) bool {
    const e1 = b - a;
    const e2 = c - a;

    const tvec = ray.origin - a;
    const pvec = math.cross3(ray.direction, e2);
    const qvec = math.cross3(tvec, e1);

    const e1_d_pv = math.dot3(e1, pvec);
    const tv_d_pv = math.dot3(tvec, pvec);
    const di_d_qv = math.dot3(ray.direction, qvec);
    const e2_d_qv = math.dot3(e2, qvec);

    const inv_det = 1.0 / e1_d_pv;

    const u = tv_d_pv * inv_det;
    const v = di_d_qv * inv_det;
    const hit_t = e2_d_qv * inv_det;

    const uv = u + v;

    if (u >= 0.0 and 1.0 >= u and v >= 0.0 and 1.0 >= uv and hit_t >= ray.minT() and ray.maxT() >= hit_t) {
        return true;
    }

    return false;
}

pub fn interpolate2(a: Vec2f, b: Vec2f, c: Vec2f, u: f32, v: f32) Vec2f {
    const w = 1.0 - u - v;
    return a.mulScalar(w).add(b.mulScalar(u)).add(c.mulScalar(v));
}

pub fn interpolate3(a: Vec4f, b: Vec4f, c: Vec4f, u: f32, v: f32) Vec4f {
    const w = 1.0 - u - v;
    return a * @splat(4, w) + b * @splat(4, u) + c * @splat(4, v);
}
