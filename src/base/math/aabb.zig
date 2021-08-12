const Vec4f = @import("vector4.zig").Vec4f;
const Mat4x4 = @import("matrix4x4.zig").Mat4x4;
const Ray = @import("ray.zig").Ray;

const std = @import("std");

const infinity = Vec4f.init1(@bitCast(f32, @as(u32, 0x7F800000)));
const neg_infinity = Vec4f.init1(@bitCast(f32, ~@as(u32, 0x7F800000)));

pub const AABB = struct {
    bounds: [2]Vec4f = undefined,

    pub fn init(min: Vec4f, max: Vec4f) AABB {
        return .{ .bounds = .{ min, max } };
    }

    pub fn surfaceArea(self: AABB) f32 {
        const d = self.bounds[1].sub3(self.bounds[0]);
        return 2.0 * (d.v[0] * d.v[1] + d.v[0] * d.v[2] + d.v[1] * d.v[2]);
    }

    pub fn intersectP(self: AABB, ray: Ray) bool {
        const l1 = self.bounds[0].sub3(ray.origin).mul3(ray.inv_direction);
        const l2 = self.bounds[1].sub3(ray.origin).mul3(ray.inv_direction);

        // the order we use for those min/max is vital to filter out
        // NaNs that happens when an inv_dir is +/- inf and
        // (box_min - pos) is 0. inf * 0 = NaN
        const filtered_l1a = l1.min3(infinity);
        const filtered_l2a = l2.min3(infinity);

        const filtered_l1b = l1.max3(neg_infinity);
        const filtered_l2b = l2.max3(neg_infinity);

        const max_t3 = filtered_l1a.max3(filtered_l2a);
        const min_t3 = filtered_l1b.min3(filtered_l2b);

        const max_t = std.math.min(max_t3.v[0], std.math.min(max_t3.v[1], max_t3.v[2]));
        const min_t = std.math.max(min_t3.v[0], std.math.max(min_t3.v[1], min_t3.v[2]));

        const ray_min_t = ray.minT();
        const ray_max_t = ray.maxT();

        return max_t >= ray_min_t and ray_max_t >= min_t and max_t >= min_t;
    }

    pub fn transform(self: AABB, m: Mat4x4) AABB {
        const mx = m.r[0];
        const xa = mx.mulScalar3(self.bounds[0].v[0]);
        const xb = mx.mulScalar3(self.bounds[1].v[0]);

        const my = m.r[1];
        const ya = my.mulScalar3(self.bounds[0].v[1]);
        const yb = my.mulScalar3(self.bounds[1].v[1]);

        const mz = m.r[2];
        const za = mz.mulScalar3(self.bounds[0].v[2]);
        const zb = mz.mulScalar3(self.bounds[1].v[2]);

        const mw = m.r[3];

        return init(
            xa.min3(xb).add3(ya.min3(yb)).add3(za.min3(zb)).add3(mw),
            xa.max3(xb).add3(ya.max3(yb)).add3(za.max3(zb)).add3(mw),
        );
    }

    pub fn mergeAssign(self: *AABB, other: AABB) void {
        self.bounds[0] = self.bounds[0].min3(other.bounds[0]);
        self.bounds[1] = self.bounds[1].max3(other.bounds[1]);
    }

    pub fn clipMin(self: *AABB, d: f32, axis: u8) void {
        self.bounds[0].v[axis] = std.math.max(d, self.bounds[0].v[axis]);
    }

    pub fn clipMax(self: *AABB, d: f32, axis: u8) void {
        self.bounds[1].v[axis] = std.math.min(d, self.bounds[1].v[axis]);
    }
};

pub const empty = AABB.init(Vec4f.init1(std.math.f32_max), Vec4f.init1(-std.math.f32_max));
