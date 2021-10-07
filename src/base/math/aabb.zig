const math = @import("vector4.zig");
const Vec4f = math.Vec4f;
const Mat4x4 = @import("matrix4x4.zig").Mat4x4;
const Ray = @import("ray.zig").Ray;

const std = @import("std");

pub const AABB = struct {
    bounds: [2]Vec4f = undefined,

    pub fn init(min: Vec4f, max: Vec4f) AABB {
        return .{ .bounds = .{ min, max } };
    }

    pub fn position(self: AABB) Vec4f {
        return @splat(4, @as(f32, 0.5)) * (self.bounds[0] + self.bounds[1]);
    }

    pub fn extent(self: AABB) Vec4f {
        return self.bounds[1] - self.bounds[0];
    }

    pub fn surfaceArea(self: AABB) f32 {
        const d = self.bounds[1] - self.bounds[0];
        return 2.0 * (d[0] * d[1] + d[0] * d[2] + d[1] * d[2]);
    }

    pub fn intersectP(self: AABB, ray: Ray) bool {
        const l1 = (self.bounds[0] - ray.origin) * ray.inv_direction;
        const l2 = (self.bounds[1] - ray.origin) * ray.inv_direction;

        // the order we use for those min/max is vital to filter out
        // NaNs that happens when an inv_dir is +/- inf and
        // (box_min - pos) is 0. inf * 0 = NaN
        const filtered_l1a = @minimum(l1, math.Infinity);
        const filtered_l2a = @minimum(l2, math.Infinity);

        const filtered_l1b = @maximum(l1, math.Neg_infinity);
        const filtered_l2b = @maximum(l2, math.Neg_infinity);

        // now that we're back on our feet, test those slabs.
        const max_t3 = @maximum(filtered_l1a, filtered_l2a);
        const min_t3 = @minimum(filtered_l1b, filtered_l2b);

        // unfold back. try to hide the latency of the shufps & co.
        var max_t = std.math.min(max_t3[0], max_t3[1]);
        var min_t = std.math.max(min_t3[0], min_t3[1]);

        max_t = std.math.min(max_t, max_t3[2]);
        min_t = std.math.max(min_t, min_t3[2]);

        const ray_min_t = ray.minT();
        const ray_max_t = ray.maxT();

        // return max_t >= ray_min_t and ray_max_t >= min_t and max_t >= min_t;
        return 0 != (@boolToInt(max_t >= ray_min_t) & @boolToInt(ray_max_t >= min_t) & @boolToInt(max_t >= min_t));
    }

    pub fn transform(self: AABB, m: Mat4x4) AABB {
        const mx = m.r[0];
        const xa = mx * @splat(4, self.bounds[0][0]);
        const xb = mx * @splat(4, self.bounds[1][0]);

        const my = m.r[1];
        const ya = my * @splat(4, self.bounds[0][1]);
        const yb = my * @splat(4, self.bounds[1][1]);

        const mz = m.r[2];
        const za = mz * @splat(4, self.bounds[0][2]);
        const zb = mz * @splat(4, self.bounds[1][2]);

        const mw = m.r[3];

        return init(
            @minimum(xa, xb) + @minimum(ya, yb) + @minimum(za, zb) + mw,
            @maximum(xa, xb) + @maximum(ya, yb) + @maximum(za, zb) + mw,
        );
    }

    pub fn mergeAssign(self: *AABB, other: AABB) void {
        self.bounds[0] = @minimum(self.bounds[0], other.bounds[0]);
        self.bounds[1] = @maximum(self.bounds[1], other.bounds[1]);
    }

    pub fn clipMin(self: *AABB, d: f32, axis: u8) void {
        self.bounds[0][axis] = @maximum(d, self.bounds[0][axis]);
    }

    pub fn clipMax(self: *AABB, d: f32, axis: u8) void {
        self.bounds[1][axis] = @minimum(d, self.bounds[1][axis]);
    }

    pub fn covers(self: AABB, other: AABB) bool {
        return self.bounds[0][0] <= other.bounds[0][0] and
            self.bounds[0][1] <= other.bounds[0][1] and
            self.bounds[0][2] <= other.bounds[0][2] and
            self.bounds[1][0] >= other.bounds[1][0] and
            self.bounds[1][1] >= other.bounds[1][1] and
            self.bounds[1][2] >= other.bounds[1][2];
    }
};

pub const empty = AABB.init(@splat(4, @as(f32, std.math.f32_max)), @splat(4, @as(f32, -std.math.f32_max)));
