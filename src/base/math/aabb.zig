const math = @import("vector4.zig");
const Vec4f = math.Vec4f;
const Mat3x3 = @import("matrix3x3.zig").Mat3x3;
const Mat4x4 = @import("matrix4x4.zig").Mat4x4;
const Ray = @import("ray.zig").Ray;

const std = @import("std");

pub const AABB = struct {
    bounds: [2]Vec4f = undefined,

    pub fn init(min: Vec4f, max: Vec4f) AABB {
        return .{ .bounds = .{ min, max } };
    }

    pub fn empty(self: AABB) bool {
        return math.equal(self.bounds[0], Empty.bounds[0]) and math.equal(self.bounds[1], Empty.bounds[1]);
    }

    pub fn position(self: AABB) Vec4f {
        return @splat(4, @as(f32, 0.5)) * (self.bounds[0] + self.bounds[1]);
    }

    pub fn halfsize(self: AABB) Vec4f {
        return @splat(4, @as(f32, 0.5)) * (self.bounds[1] - self.bounds[0]);
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

        const t0 = math.min4(lower, upper);
        const t1 = math.max4(lower, upper);

        const tmins = Vec4f{ t0[0], t0[1], t0[2], ray.minT() };
        const tmaxs = Vec4f{ t1[0], t1[1], t1[2], ray.maxT() };

        const tboxmin = std.math.max(tmins[0], std.math.max(tmins[1], std.math.max(tmins[2], tmins[3])));
        const tboxmax = std.math.min(tmaxs[0], std.math.min(tmaxs[1], std.math.min(tmaxs[2], tmaxs[3])));

        return tboxmin <= tboxmax;
    }

    pub fn intersectP(self: AABB, ray: Ray) ?f32 {
        const lower = (self.bounds[0] - ray.origin) * ray.inv_direction;
        const upper = (self.bounds[1] - ray.origin) * ray.inv_direction;

        const t0 = math.min4(lower, upper);
        const t1 = math.max4(lower, upper);

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

    pub fn intersectP2(self: AABB, ray: Ray) ?[2]f32 {
        const lower = (self.bounds[0] - ray.origin) * ray.inv_direction;
        const upper = (self.bounds[1] - ray.origin) * ray.inv_direction;

        const t0 = math.min4(lower, upper);
        const t1 = math.max4(lower, upper);

        const tmins = Vec4f{ t0[0], t0[1], t0[2], ray.minT() };
        const tmaxs = Vec4f{ t1[0], t1[1], t1[2], ray.maxT() };

        const imin = std.math.max(tmins[0], std.math.max(tmins[1], tmins[2]));
        const imax = std.math.min(tmaxs[0], std.math.min(tmaxs[1], tmaxs[2]));

        const tboxmin = std.math.max(imin, tmins[3]);
        const tboxmax = std.math.min(imax, tmaxs[3]);

        if (tboxmin <= tboxmax) {
            return .{ imin, imax };
        }

        return null;
    }

    pub fn pointInside(self: AABB, p: Vec4f) bool {
        if (p[0] >= self.bounds[0][0] and p[0] <= self.bounds[1][0] and p[1] >= self.bounds[0][1] and
            p[1] <= self.bounds[1][1] and p[2] >= self.bounds[0][2] and p[2] <= self.bounds[1][2])
        {
            return true;
        }

        return false;
    }

    pub fn insert(self: *AABB, p: Vec4f) void {
        self.bounds[0] = math.min4(p, self.bounds[0]);
        self.bounds[1] = math.max4(p, self.bounds[1]);
    }

    pub fn scale(self: *AABB, s: f32) void {
        const v = @splat(4, s) * self.halfsize();
        self.bounds[0] -= v;
        self.bounds[1] += v;
    }

    pub fn add(self: *AABB, s: f32) void {
        const v = @splat(4, s);
        self.bounds[0] -= v;
        self.bounds[1] += v;
    }

    pub fn translate(self: *AABB, v: Vec4f) void {
        self.bounds[0] += v;
        self.bounds[1] += v;
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
            math.min4(xa, xb) + math.min4(ya, yb) + math.min4(za, zb) + mw,
            math.max4(xa, xb) + math.max4(ya, yb) + math.max4(za, zb) + mw,
        );
    }

    pub fn transformTransposed(self: AABB, m: Mat3x3) AABB {
        const mx = Vec4f{ m.r[0][0], m.r[1][0], m.r[2][0], 0.0 };
        const xa = @splat(4, self.bounds[0][0]) * mx;
        const xb = @splat(4, self.bounds[1][0]) * mx;

        const my = Vec4f{ m.r[0][1], m.r[1][1], m.r[2][1], 0.0 };
        const ya = @splat(4, self.bounds[0][1]) * my;
        const yb = @splat(4, self.bounds[1][1]) * my;

        const mz = Vec4f{ m.r[0][2], m.r[1][2], m.r[2][2], 0.0 };
        const za = @splat(4, self.bounds[0][2]) * mz;
        const zb = @splat(4, self.bounds[1][2]) * mz;

        const min = math.min4(xa, xb) + math.min4(ya, yb) + math.min4(za, zb);
        const max = math.max4(xa, xb) + math.max4(ya, yb) + math.max4(za, zb);

        const half = @splat(4, @as(f32, 0.5)) * (max - min);

        const p = self.position();

        return init(p - half, p + half);
    }

    pub fn intersection(self: AABB, other: AABB) AABB {
        return init(
            math.max4(self.bounds[0], other.bounds[0]),
            math.min4(self.bounds[1], other.bounds[1]),
        );
    }

    pub fn mergeAssign(self: *AABB, other: AABB) void {
        self.bounds[0] = math.min4(self.bounds[0], other.bounds[0]);
        self.bounds[1] = math.max4(self.bounds[1], other.bounds[1]);
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

pub const Empty = AABB.init(@splat(4, @as(f32, std.math.f32_max)), @splat(4, @as(f32, -std.math.f32_max)));
