const curve = @import("curve.zig");
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const int = @import("../intersection.zig");
const Intersection = int.Intersection;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Mesh = struct {
    num_curves: u32,

    points: [*]f32,
    widths: [*]Vec2f,

    aabb: AABB = undefined,

    pub fn init(alloc: Allocator, num_curves: u32) !Mesh {
        const points = try alloc.alloc(f32, num_curves * 4 * 3 + 1);

        points[0 * 3 + 0] = 0.0;
        points[0 * 3 + 1] = 0.0;
        points[0 * 3 + 2] = 0.0;

        points[1 * 3 + 0] = -0.25;
        points[1 * 3 + 1] = 0.33;
        points[1 * 3 + 2] = 0.3;

        points[2 * 3 + 0] = 0.125;
        points[2 * 3 + 1] = 0.66;
        points[2 * 3 + 2] = 0.6;

        points[3 * 3 + 0] = 0.0;
        points[3 * 3 + 1] = 1.0;
        points[3 * 3 + 2] = 0.4;

        points[4 * 3 + 0] = 0.4;
        points[4 * 3 + 1] = 0.0;
        points[4 * 3 + 2] = 0.0;

        points[5 * 3 + 0] = 0.15;
        points[5 * 3 + 1] = 0.33;
        points[5 * 3 + 2] = 0.6;

        points[6 * 3 + 0] = 0.525;
        points[6 * 3 + 1] = 0.66;
        points[6 * 3 + 2] = 0.3;

        points[7 * 3 + 0] = 0.4;
        points[7 * 3 + 1] = 1.0;
        points[7 * 3 + 2] = 0.4;

        points[num_curves * 4 * 3] = 0.0;

        const widths = try alloc.alloc(Vec2f, num_curves);

        widths[0] = Vec2f{ 0.2, 0.025 };
        widths[1] = Vec2f{ 0.1, 0.0125 };

        return .{ .num_curves = num_curves, .points = points.ptr, .widths = widths.ptr };
    }

    pub fn HACK_setCurve(self: *Mesh, id: u32, points: [4]Vec4f, width: Vec2f) void {
        const offset = id * 4 * 3;
        var dest = self.points[offset .. offset + 4 * 3];

        dest[0] = points[0][0];
        dest[1] = points[0][1];
        dest[2] = points[0][2];

        dest[3] = points[1][0];
        dest[4] = points[1][1];
        dest[5] = points[1][2];

        dest[6] = points[2][0];
        dest[7] = points[2][1];
        dest[8] = points[2][2];

        dest[9] = points[3][0];
        dest[10] = points[3][1];
        dest[11] = points[3][2];

        self.widths[id] = width;
    }

    pub fn HACK_computeBounds(self: *Mesh) void {
        var bounds = math.aabb.Empty;

        for (0..self.num_curves) |i| {
            var box = curve.cubicBezierBounds(self.curvePoints(@intCast(i)));

            const width = self.widths[i];
            box.expand(math.max(width[0], width[1]) * 0.5);

            bounds.mergeAssign(box);
        }

        self.aabb = bounds;
    }

    pub fn deinit(self: *Mesh, alloc: Allocator) void {
        alloc.free(self.widths[0..self.num_curves]);
        alloc.free(self.points[0 .. self.num_curves * 4 * 3 + 1]);
    }

    inline fn curvePoints(self: Mesh, id: u32) [4]Vec4f {
        const offset = id * 4 * 3;

        return .{
            self.points[offset + 0 ..][0..4].*,
            self.points[offset + 3 ..][0..4].*,
            self.points[offset + 6 ..][0..4].*,
            self.points[offset + 9 ..][0..4].*,
        };
    }

    pub fn intersect(self: Mesh, ray: *Ray, trafo: Trafo, isec: *Intersection) bool {
        var local_ray = trafo.worldToObjectRay(ray.*);

        var cube_ray = local_ray;

        for (0..self.num_curves) |i| {
            const id: u32 = @intCast(i);
            const cp = self.curvePoints(id);

            var box = curve.cubicBezierBounds(cp);
            const width = self.widths[i];
            box.expand(math.max(width[0], width[1]) * 0.5);
            if (!box.intersect(local_ray)) {
                continue;
            }

            if (self.recursiveIntersectSegment(local_ray, id, cp, .{ 0.0, 1.0 }, 0)) |result_ray| {
                cube_ray = result_ray;
                local_ray.setMaxT(result_ray.maxT());
            }
        }

        const hit_t = cube_ray.maxT();

        if (ray.maxT() == hit_t) {
            return false;
        }

        ray.setMaxT(hit_t);

        isec.p = ray.point(hit_t);

        const cube_p = cube_ray.point(hit_t);
        const distance = @fabs(@splat(4, @as(f32, 1.0)) - @fabs(cube_p));

        const i = math.indexMinComponent3(distance);
        const s = std.math.copysign(@as(f32, 1.0), cube_p[i]);
        const n = @splat(4, s) * trafo.rotation.r[i];

        isec.part = 0;
        isec.primitive = 0;
        isec.geo_n = n;
        isec.n = n;

        return true;
    }

    fn segmentBounds(self: Mesh, id: u32, points: [4]Vec4f, u_mima: Vec2f) AABB {
        var bounds = curve.cubicBezierBounds(points);

        const width = self.widths[id];
        const w0 = math.lerp(width[0], width[1], u_mima[0]);
        const w1 = math.lerp(width[0], width[1], u_mima[1]);

        bounds.expand(math.max(w0, w1) * 0.5);

        return bounds;
    }

    fn linearSegmentBounds(self: Mesh, id: u32, points: [4]Vec4f, u_mima: Vec2f) AABB {
        var bounds = AABB.init(math.min4(points[0], points[3]), math.max4(points[0], points[3]));

        const width = self.widths[id];
        const w0 = math.lerp(width[0], width[1], u_mima[0]);
        const w1 = math.lerp(width[0], width[1], u_mima[1]);

        bounds.expand(math.max(w0, w1) * 0.5);

        return bounds;
    }

    fn intersectSegment(self: Mesh, ray: Ray, id: u32, points: [4]Vec4f, u_mima: Vec2f) ?Ray {
        const aabb = self.linearSegmentBounds(id, points, u_mima);
        var cube_ray = aabb.objectToCubeRay(ray);

        const unit = AABB.init(@splat(4, @as(f32, -1.0)), @splat(4, @as(f32, 1.0)));
        const hit_t = unit.intersectP(cube_ray) orelse return null;
        if (hit_t > ray.maxT()) {
            return null;
        }

        cube_ray.setMaxT(hit_t);
        return cube_ray;
    }

    fn recursiveIntersectSegment(self: Mesh, ray: Ray, id: u32, points: [4]Vec4f, u_mima: Vec2f, depth: u32) ?Ray {
        if (5 == depth) {
            return self.intersectSegment(ray, id, points, u_mima);
        }

        const segments = curve.cubicBezierSubdivide(points);

        var local_ray = ray;
        var cube_ray = ray;

        const u_middle = 0.5 * u_mima[1];
        const next_depth = depth + 1;

        if (self.recursiveIntersectSegment(local_ray, id, segments[0..4].*, .{ u_mima[0], u_middle }, next_depth)) |result_ray| {
            cube_ray = result_ray;
            local_ray.setMaxT(result_ray.maxT());
        }

        if (self.recursiveIntersectSegment(local_ray, id, segments[3..7].*, .{ u_middle, u_mima[1] }, next_depth)) |result_ray| {
            cube_ray = result_ray;
        }

        const hit_t = cube_ray.maxT();

        if (ray.maxT() == hit_t) {
            return null;
        }

        return cube_ray;
    }

    fn intersectSegmentP(self: Mesh, ray: Ray, id: u32, points: [4]Vec4f, u_mima: Vec2f) bool {
        const aabb = self.linearSegmentBounds(id, points, u_mima);
        var cube_ray = aabb.objectToCubeRay(ray);

        const unit = AABB.init(@splat(4, @as(f32, -1.0)), @splat(4, @as(f32, 1.0)));
        return unit.intersect(cube_ray);
    }

    fn recursiveIntersectSegmentP(self: Mesh, ray: Ray, id: u32, points: [4]Vec4f, u_mima: Vec2f, depth: u32) bool {
        if (5 == depth) {
            return self.intersectSegmentP(ray, id, points, u_mima);
        }

        const segments = curve.cubicBezierSubdivide(points);

        const u_middle = 0.5 * u_mima[1];
        const next_depth = depth + 1;

        if (self.recursiveIntersectSegmentP(ray, id, segments[0..4].*, .{ u_mima[0], u_middle }, next_depth)) {
            return true;
        }

        return self.recursiveIntersectSegmentP(ray, id, segments[3..7].*, .{ u_middle, u_mima[1] }, next_depth);
    }

    pub fn intersectP(self: Mesh, ray: Ray, trafo: Trafo) bool {
        const local_ray = trafo.worldToObjectRay(ray);

        for (0..self.num_curves) |i| {
            const id: u32 = @intCast(i);
            const cp = self.curvePoints(id);

            var box = curve.cubicBezierBounds(cp);
            const width = self.widths[i];
            box.expand(math.max(width[0], width[1]) * 0.5);
            if (!box.intersect(local_ray)) {
                continue;
            }

            if (self.recursiveIntersectSegmentP(local_ray, id, cp, .{ 0.0, 1.0 }, 0)) {
                return true;
            }
        }

        return false;
    }

    pub fn visibility(self: Mesh, ray: Ray, trafo: Trafo) ?Vec4f {
        return if (self.intersectP(ray, trafo)) null else @splat(4, @as(f32, 1.0));
    }
};
