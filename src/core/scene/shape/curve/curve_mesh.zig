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

pub const Mesh = struct {
    points: [4]Vec4f,
    width: [2]f32,

    aabb: AABB,

    pub fn init() Mesh {
        const points: [4]Vec4f = .{
            .{ 0.0, 0.0, 0.0, 0.0 },
            .{ -0.25, 0.33, 0.3, 0.0 },
            .{ 0.125, 0.66, 0.6, 0.0 },
            .{ 0.0, 1.0, 0.4, 0.0 },
        };

        const width: [2]f32 = .{ 0.2, 0.025 };

        var bounds = curve.cubicBezierBounds(points);
        bounds.expand(math.max(width[0], width[1]) * 0.5);

        return .{ .points = points, .width = width, .aabb = bounds };
    }

    pub fn intersect(self: Mesh, ray: *Ray, trafo: Trafo, isec: *Intersection) bool {
        var local_ray = trafo.worldToObjectRay(ray.*);

        // const segments = curve.cubicBezierSubdivide(self.points);

        // var cube_ray = local_ray;

        // if (self.intersectSegmentP(local_ray, segments[0..4].*, .{ 0.0, 0.5 })) |result_ray| {
        //     cube_ray = result_ray;
        //     local_ray.setMaxT(result_ray.maxT());
        // }

        // if (self.intersectSegmentP(local_ray, segments[3..7].*, .{ 0.5, 1.0 })) |result_ray| {
        //     cube_ray = result_ray;
        //     local_ray.setMaxT(result_ray.maxT());
        // }

        var cube_ray = local_ray;
        if (self.recursiveIntersectSegment(local_ray, self.points, .{ 0.0, 1.0 }, 0)) |result_ray| {
            cube_ray = result_ray;
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

    fn segmentBounds(self: Mesh, points: [4]Vec4f, u_mima: Vec2f) AABB {
        var bounds = curve.cubicBezierBounds(points);

        const w0 = math.lerp(self.width[0], self.width[1], u_mima[0]);
        const w1 = math.lerp(self.width[0], self.width[1], u_mima[1]);

        bounds.expand(math.max(w0, w1) * 0.5);

        return bounds;
    }

    fn intersectSegment(self: Mesh, ray: Ray, points: [4]Vec4f, u_mima: Vec2f) ?Ray {
        const aabb = self.segmentBounds(points, u_mima);
        var cube_ray = aabb.objectToCubeRay(ray);

        const unit = AABB.init(@splat(4, @as(f32, -1.0)), @splat(4, @as(f32, 1.0)));
        const hit_t = unit.intersectP(cube_ray) orelse return null;
        if (hit_t > ray.maxT()) {
            return null;
        }

        cube_ray.setMaxT(hit_t);
        return cube_ray;
    }

    fn recursiveIntersectSegment(self: Mesh, ray: Ray, points: [4]Vec4f, u_mima: Vec2f, depth: u32) ?Ray {
        if (5 == depth) {
            return self.intersectSegment(ray, points, u_mima);
        }

        const segments = curve.cubicBezierSubdivide(points);

        var local_ray = ray;
        var cube_ray = ray;

        const u_middle = 0.5 * u_mima[1];
        const next_depth = depth + 1;

        if (self.recursiveIntersectSegment(local_ray, segments[0..4].*, .{ u_mima[0], u_middle }, next_depth)) |result_ray| {
            cube_ray = result_ray;
            local_ray.setMaxT(result_ray.maxT());
        }

        if (self.recursiveIntersectSegment(local_ray, segments[3..7].*, .{ u_middle, u_mima[1] }, next_depth)) |result_ray| {
            cube_ray = result_ray;
        }

        const hit_t = cube_ray.maxT();

        if (ray.maxT() == hit_t) {
            return null;
        }

        return cube_ray;
    }

    fn intersectSegmentP(self: Mesh, ray: Ray, points: [4]Vec4f, u_mima: Vec2f) bool {
        const aabb = self.segmentBounds(points, u_mima);
        var cube_ray = aabb.objectToCubeRay(ray);

        const unit = AABB.init(@splat(4, @as(f32, -1.0)), @splat(4, @as(f32, 1.0)));
        return unit.intersect(cube_ray);
    }

    fn recursiveIntersectSegmentP(self: Mesh, ray: Ray, points: [4]Vec4f, u_mima: Vec2f, depth: u32) bool {
        if (5 == depth) {
            return self.intersectSegmentP(ray, points, u_mima);
        }

        const segments = curve.cubicBezierSubdivide(points);

        const u_middle = 0.5 * u_mima[1];
        const next_depth = depth + 1;

        if (self.recursiveIntersectSegmentP(ray, segments[0..4].*, .{ u_mima[0], u_middle }, next_depth)) {
            return true;
        }

        return self.recursiveIntersectSegmentP(ray, segments[3..7].*, .{ u_middle, u_mima[1] }, next_depth);
    }

    pub fn intersectP(self: Mesh, ray: Ray, trafo: Trafo) bool {
        const local_ray = trafo.worldToObjectRay(ray);
        return self.recursiveIntersectSegmentP(local_ray, self.points, .{ 0.0, 1.0 }, 0);
    }

    pub fn visibility(self: Mesh, ray: Ray, trafo: Trafo) ?Vec4f {
        return if (self.intersectP(ray, trafo)) null else @splat(4, @as(f32, 1.0));
    }
};
