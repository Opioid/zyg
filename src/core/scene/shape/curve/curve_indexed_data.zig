const CurveBuffer = @import("curve_buffer.zig").Buffer;
const curve = @import("curve.zig");

const math = @import("base").math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const IndexedData = struct {
    num_indices: u32 = 0,
    num_curves: u32 = 0,

    indices: [*]u32 = undefined,
    points: [*]f32 = undefined,
    widths: [*]f32 = undefined,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.widths[0 .. self.num_curves * 2]);
        alloc.free(self.points[0 .. self.num_curves * 4 * 3 + 1]);
        alloc.free(self.indices[0..self.num_indices]);
    }

    pub fn allocateCurves(self: *Self, alloc: Allocator, num_indices: u32, num_curves: u32, curves: CurveBuffer) !void {
        self.num_indices = num_indices;
        self.num_curves = num_curves;

        self.indices = (try alloc.alloc(u32, num_indices)).ptr;

        self.points = (try alloc.alloc(f32, num_curves * 4 * 3 + 1)).ptr;
        self.widths = (try alloc.alloc(f32, num_curves * 2)).ptr;

        curves.copy(self.points, self.widths, num_curves);
        self.points[num_curves * 4 * 3] = 0.0;
    }

    pub fn setCurve(self: *Self, curve_id: u32, index: u32) void {
        self.indices[curve_id] = index;
    }

    pub fn intersect(self: *const Self, ray: Ray, id: u32) ?Ray {
        const index = self.indices[id];

        const cp = self.curvePoints(index);
        var box = curve.cubicBezierBounds(cp);
        const width0 = self.widths[index * 2 + 0];
        const width1 = self.widths[index * 2 + 1];
        box.expand(math.max(width0, width1) * 0.5);

        if (!box.intersect(ray)) {
            return null;
        }

        return self.recursiveIntersectSegment(ray, index, cp, .{ 0.0, 1.0 }, 0);
    }

    pub fn intersectP(self: *const Self, ray: Ray, id: u32) bool {
        const index = self.indices[id];

        const cp = self.curvePoints(index);
        var box = curve.cubicBezierBounds(cp);
        const width0 = self.widths[index * 2 + 0];
        const width1 = self.widths[index * 2 + 1];
        box.expand(math.max(width0, width1) * 0.5);

        if (!box.intersect(ray)) {
            return false;
        }

        return self.recursiveIntersectSegmentP(ray, index, cp, .{ 0.0, 1.0 }, 0);
    }

    fn recursiveIntersectSegment(self: *const Self, ray: Ray, index: u32, points: [4]Vec4f, u_mima: Vec2f, depth: u32) ?Ray {
        if (5 == depth) {
            return self.intersectSegment(ray, index, points, u_mima);
        }

        const segments = curve.cubicBezierSubdivide(points);

        var local_ray = ray;
        var cube_ray = ray;

        const u_middle = 0.5 * u_mima[1];
        const next_depth = depth + 1;

        if (self.recursiveIntersectSegment(local_ray, index, segments[0..4].*, .{ u_mima[0], u_middle }, next_depth)) |result_ray| {
            cube_ray = result_ray;
            local_ray.setMaxT(result_ray.maxT());
        }

        if (self.recursiveIntersectSegment(local_ray, index, segments[3..7].*, .{ u_middle, u_mima[1] }, next_depth)) |result_ray| {
            cube_ray = result_ray;
        }

        const hit_t = cube_ray.maxT();

        if (ray.maxT() == hit_t) {
            return null;
        }

        return cube_ray;
    }

    fn recursiveIntersectSegmentP(self: *const Self, ray: Ray, index: u32, points: [4]Vec4f, u_mima: Vec2f, depth: u32) bool {
        if (5 == depth) {
            return self.intersectSegmentP(ray, index, points, u_mima);
        }

        const segments = curve.cubicBezierSubdivide(points);

        const u_middle = 0.5 * u_mima[1];
        const next_depth = depth + 1;

        if (self.recursiveIntersectSegmentP(ray, index, segments[0..4].*, .{ u_mima[0], u_middle }, next_depth)) {
            return true;
        }

        return self.recursiveIntersectSegmentP(ray, index, segments[3..7].*, .{ u_middle, u_mima[1] }, next_depth);
    }

    fn intersectSegment(self: *const Self, ray: Ray, index: u32, points: [4]Vec4f, u_mima: Vec2f) ?Ray {
        const aabb = self.linearSegmentBounds(index, points, u_mima);
        var cube_ray = aabb.objectToCubeRay(ray);

        const unit = AABB.init(@splat(4, @as(f32, -1.0)), @splat(4, @as(f32, 1.0)));
        const hit_t = unit.intersectP(cube_ray) orelse return null;
        if (hit_t > ray.maxT()) {
            return null;
        }

        cube_ray.setMaxT(hit_t);
        return cube_ray;
    }

    fn intersectSegmentP(self: *const Self, ray: Ray, index: u32, points: [4]Vec4f, u_mima: Vec2f) bool {
        const aabb = self.linearSegmentBounds(index, points, u_mima);
        var cube_ray = aabb.objectToCubeRay(ray);

        const unit = AABB.init(@splat(4, @as(f32, -1.0)), @splat(4, @as(f32, 1.0)));
        return unit.intersect(cube_ray);
    }

    fn linearSegmentBounds(self: *const Self, index: u32, points: [4]Vec4f, u_mima: Vec2f) AABB {
        var bounds = AABB.init(math.min4(points[0], points[3]), math.max4(points[0], points[3]));

        const width0 = self.widths[index * 2 + 0];
        const width1 = self.widths[index * 2 + 1];

        const w0 = math.lerp(width0, width1, u_mima[0]);
        const w1 = math.lerp(width0, width1, u_mima[1]);

        bounds.expand(math.max(w0, w1) * 0.5);

        return bounds;
    }

    inline fn curvePoints(self: *const Self, index: u32) [4]Vec4f {
        const offset = index * 4 * 3;

        return .{
            self.points[offset + 0 ..][0..4].*,
            self.points[offset + 3 ..][0..4].*,
            self.points[offset + 6 ..][0..4].*,
            self.points[offset + 9 ..][0..4].*,
        };
    }
};
