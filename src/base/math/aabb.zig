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

    // Raytracing Gems 2 - chapter 2
    pub fn intersect(self: AABB, ray: Ray) bool {
        const lower = (self.bounds[0] - ray.origin) * ray.inv_direction;
        const upper = (self.bounds[1] - ray.origin) * ray.inv_direction;

        const t0 = @minimum(lower, upper);
        const t1 = @maximum(lower, upper);

        const tmins = Vec4f{ t0[0], t0[1], t0[2], ray.minT() };
        const tmaxs = Vec4f{ t1[0], t1[1], t1[2], ray.maxT() };

        const tboxmin = std.math.max(tmins[0], std.math.max(tmins[1], std.math.max(tmins[2], tmins[3])));
        const tboxmax = std.math.min(tmaxs[0], std.math.min(tmaxs[1], std.math.min(tmaxs[2], tmaxs[3])));

        return tboxmin <= tboxmax;
    }

    pub fn intersectP(self: AABB, ray: Ray) ?f32 {
        const lower = (self.bounds[0] - ray.origin) * ray.inv_direction;
        const upper = (self.bounds[1] - ray.origin) * ray.inv_direction;

        const t0 = @minimum(lower, upper);
        const t1 = @maximum(lower, upper);

        const tmins = Vec4f{ t0[0], t0[1], t0[2], ray.minT() };
        const tmaxs = Vec4f{ t1[0], t1[1], t1[2], ray.maxT() };

        const imin = std.math.max(tmins[0], std.math.max(tmins[1], tmins[2]));
        const imax = std.math.min(tmaxs[0], std.math.min(tmaxs[1], tmaxs[2]));

        const tboxmin = std.math.max(imin, tmins[3]);
        const tboxmax = std.math.min(imax, tmaxs[3]);

        if (tboxmin <= tboxmax) {
            return if (imin < ray.minT()) imax else imin;
        }

        return null;
    }

    pub fn insert(self: *AABB, p: Vec4f) void {
        self.bounds[0] = @minimum(p, self.bounds[0]);
        self.bounds[1] = @maximum(p, self.bounds[1]);
    }

    pub fn cachedRadius(self: AABB) f32 {
        return self.bounds[0][3];
    }

    pub fn cacheRadius(self: *AABB) void {
        self.bounds[0][3] = 0.5 * math.length3(self.extent());
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
        self.bounds[0][axis] = std.math.max(d, self.bounds[0][axis]);
    }

    pub fn clipMax(self: *AABB, d: f32, axis: u8) void {
        self.bounds[1][axis] = std.math.min(d, self.bounds[1][axis]);
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
