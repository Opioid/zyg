const CurveBuffer = @import("curve_buffer.zig").Buffer;
const curve = @import("curve.zig");

const math = @import("base").math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const IndexedData = struct {
    pub const Intersection = struct {
        geo_n: Vec4f = undefined,
        dpdu: Vec4f = undefined,
        dpdv: Vec4f = undefined,
        t: f32 = undefined,
        u: f32 = undefined,
        index: u32 = 0xFFFFFFFF,
    };

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

    pub fn curveWidth(self: *const Self, id: u32, u: f32) f32 {
        const index = self.indices[id];

        const width0 = self.widths[index * 2 + 0];
        const width1 = self.widths[index * 2 + 1];

        return math.lerp(width0, width1, u);
    }

    pub fn intersect(self: *const Self, ray: Ray, id: u32, isec: *Intersection) bool {
        const index = self.indices[id];

        const cp = self.curvePoints(index);

        var dx = math.cross3(ray.direction, cp[3] - cp[0]);
        if (0.0 == math.squaredLength3(dx)) {
            dx = math.tangent3(ray.direction);
        }

        const ray_to_object = math.Mat4x4.initLookAt(ray.origin, ray.direction, dx);

        const cpr: [4]Vec4f = .{
            ray_to_object.transformPointTransposed(cp[0]),
            ray_to_object.transformPointTransposed(cp[1]),
            ray_to_object.transformPointTransposed(cp[2]),
            ray_to_object.transformPointTransposed(cp[3]),
        };

        var box = curve.cubicBezierBounds(cpr);
        const width0 = self.widths[index * 2 + 0];
        const width1 = self.widths[index * 2 + 1];
        box.expand(math.max(width0, width1) * 0.5);

        const ray_bounds = AABB.init(@splat(4, @as(f32, 0.0)), .{ 0.0, 0.0, math.length3(ray.direction) * ray.maxT(), 0.0 });

        if (!box.overlaps(ray_bounds)) {
            return false;
        }

        return self.recursiveIntersectSegment(ray, ray_to_object, index, cpr, .{ 0.0, 1.0 }, 5, isec);
    }

    pub fn intersectP(self: *const Self, ray: Ray, id: u32) bool {
        const index = self.indices[id];

        const cp = self.curvePoints(index);

        var dx = math.cross3(ray.direction, cp[3] - cp[0]);
        if (0.0 == math.squaredLength3(dx)) {
            dx = math.tangent3(ray.direction);
        }

        const rayToObject = math.Mat4x4.initLookAt(ray.origin, ray.direction, dx);

        const cpr: [4]Vec4f = .{
            rayToObject.transformPointTransposed(cp[0]),
            rayToObject.transformPointTransposed(cp[1]),
            rayToObject.transformPointTransposed(cp[2]),
            rayToObject.transformPointTransposed(cp[3]),
        };

        var box = curve.cubicBezierBounds(cpr);
        const width0 = self.widths[index * 2 + 0];
        const width1 = self.widths[index * 2 + 1];
        box.expand(math.max(width0, width1) * 0.5);

        const ray_bounds = AABB.init(@splat(4, @as(f32, 0.0)), .{ 0.0, 0.0, math.length3(ray.direction) * ray.maxT(), 0.0 });

        if (!box.overlaps(ray_bounds)) {
            return false;
        }

        return self.recursiveIntersectSegmentP(ray, index, cpr, .{ 0.0, 1.0 }, 5);
    }

    fn recursiveIntersectSegment(
        self: *const Self,
        ray: Ray,
        ray_to_object: Mat4x4,
        index: u32,
        cp: [4]Vec4f,
        u_range: Vec2f,
        depth: u32,
        isec: *Intersection,
    ) bool {
        if (0 == depth) {
            return self.intersectSegment(ray, ray_to_object, index, cp, u_range, isec);
        }

        const segments = curve.cubicBezierSubdivide(cp);

        var tray = ray;

        const u_middle = 0.5 * (u_range[0] + u_range[1]);
        const next_depth = depth - 1;

        const hit0 = self.recursiveIntersectSegment(tray, ray_to_object, index, segments[0..4].*, .{ u_range[0], u_middle }, next_depth, isec);
        if (hit0) {
            tray.setMaxT(isec.t);
        }

        const hit1 = self.recursiveIntersectSegment(tray, ray_to_object, index, segments[3..7].*, .{ u_middle, u_range[1] }, next_depth, isec);

        return hit0 or hit1;
    }

    fn intersectSegment(
        self: *const Self,
        ray: Ray,
        ray_to_object: Mat4x4,
        index: u32,
        cp: [4]Vec4f,
        u_range: Vec2f,
        isec: *Intersection,
    ) bool {
        // Test sample point against tangent perpendicular at curve start
        const edge0 = (cp[1][1] - cp[0][1]) * -cp[0][1] + cp[0][0] * (cp[0][0] - cp[1][0]);
        if (edge0 < 0.0) {
            return false;
        }

        // Test sample point against tangent perpendicular at curve end
        const edge1 = (cp[2][1] - cp[3][1]) * -cp[3][1] + cp[3][0] * (cp[3][0] - cp[2][0]);
        if (edge1 < 0.0) {
            return false;
        }

        // Find line w that gives minimum distance to sample point
        const segment_dir = Vec2f{ cp[3][0], cp[3][1] } - Vec2f{ cp[0][0], cp[0][1] };
        const denom = math.squaredLength2(segment_dir);
        if (0.0 == denom) {
            return false;
        }

        const w = math.dot2(-Vec2f{ cp[0][0], cp[0][1] }, segment_dir) / denom;

        // Compute u coordinate of curve intersection point and _hitWidth_
        const u = math.clamp(math.lerp(u_range[0], u_range[1], w), u_range[0], u_range[1]);

        const width0 = self.widths[index * 2 + 0];
        const width1 = self.widths[index * 2 + 1];
        const hit_width = math.lerp(width0, width1, u);

        const eval = curve.cubicBezierEvaluateWithDerivative(cp, math.clamp(w, 0.0, 1.0));
        const pc = eval[0];

        const pt_curve_dist2 = pc[0] * pc[0] + pc[1] * pc[1];
        if (pt_curve_dist2 > (hit_width * hit_width) * 0.25) {
            return false;
        }

        const ray_length = math.length3(ray.direction);
        if (pc[2] < 0.0 or pc[2] > ray_length * ray.maxT()) {
            return false;
        }

        const hit_t = pc[2] / ray_length;
        if (hit_t > ray.maxT()) {
            return false;
        }

        const crap = curve.cubicBezierEvaluateDerivative(self.curvePoints(index), u);
        const dpdu = -Vec4f{ crap[0], crap[1], crap[2], 0.0 };

        const dpdu_plane = ray_to_object.transformVectorTransposed(dpdu);
        var dpdv_plane = math.normalize3(Vec4f{ dpdu_plane[1], -dpdu_plane[0], 0.0, 0.0 }) * @splat(4, hit_width);

        const geo_n = math.normalize3(math.cross3(dpdu, ray_to_object.transformVector(dpdv_plane)));

        {
            // Rotate dpdv_plane to give cylindrical appearance
            const dpcdw = eval[1];

            const pt_curve_dist = @sqrt(pt_curve_dist2);
            const edge_func = -pc[1] * dpcdw[0] + pc[0] * dpcdw[1];
            const v = if (edge_func > 0.0) 0.5 + pt_curve_dist / hit_width else 0.5 - pt_curve_dist / hit_width;

            const theta = math.lerp(math.degreesToRadians(@as(f32, -90.0)), math.degreesToRadians(@as(f32, 90.0)), v);
            const rot = Mat3x3.initRotation(dpdu_plane, theta);
            dpdv_plane = rot.transformVector(dpdv_plane);
        }

        const dpdv = ray_to_object.transformVector(dpdv_plane);

        //   std.debug.print("{}\n", .{dpdu_plane});

        isec.geo_n = geo_n;
        isec.dpdu = dpdu;
        isec.dpdv = dpdv;
        isec.t = hit_t;
        isec.u = u;
        return true;
    }

    fn recursiveIntersectSegmentP(self: *const Self, ray: Ray, index: u32, cp: [4]Vec4f, u_range: Vec2f, depth: u32) bool {
        if (0 == depth) {
            return self.intersectSegmentP(ray, index, cp, u_range);
        }

        const segments = curve.cubicBezierSubdivide(cp);

        const u_middle = 0.5 * (u_range[0] + u_range[1]);
        const next_depth = depth - 1;

        if (self.recursiveIntersectSegmentP(ray, index, segments[0..4].*, .{ u_range[0], u_middle }, next_depth)) {
            return true;
        }

        return self.recursiveIntersectSegmentP(ray, index, segments[3..7].*, .{ u_middle, u_range[1] }, next_depth);
    }

    fn intersectSegmentP(self: *const Self, ray: Ray, index: u32, cp: [4]Vec4f, u_range: Vec2f) bool {
        // Test sample point against tangent perpendicular at curve start
        const edge0 = (cp[1][1] - cp[0][1]) * -cp[0][1] + cp[0][0] * (cp[0][0] - cp[1][0]);
        if (edge0 < 0.0) {
            return false;
        }

        // Test sample point against tangent perpendicular at curve end
        const edge1 = (cp[2][1] - cp[3][1]) * -cp[3][1] + cp[3][0] * (cp[3][0] - cp[2][0]);
        if (edge1 < 0.0) {
            return false;
        }

        // Find line w that gives minimum distance to sample point
        const segment_dir = Vec2f{ cp[3][0], cp[3][1] } - Vec2f{ cp[0][0], cp[0][1] };
        const denom = math.squaredLength2(segment_dir);
        if (0.0 == denom) {
            return false;
        }

        const w = math.dot2(-Vec2f{ cp[0][0], cp[0][1] }, segment_dir) / denom;

        // Compute u coordinate of curve intersection point and _hitWidth_
        const u = math.clamp(math.lerp(u_range[0], u_range[1], w), u_range[0], u_range[1]);

        const width0 = self.widths[index * 2 + 0];
        const width1 = self.widths[index * 2 + 1];
        const hit_width = math.lerp(width0, width1, u);

        const pc = curve.cubicBezierEvaluate(cp, math.clamp(w, 0.0, 1.0));

        const pt_curve_dist2 = pc[0] * pc[0] + pc[1] * pc[1];
        if (pt_curve_dist2 > (hit_width * hit_width) * 0.25) {
            return false;
        }

        const ray_length = math.length3(ray.direction);
        if (pc[2] < 0 or pc[2] > ray_length * ray.maxT()) {
            return false;
        }

        const hit_t = pc[2] / ray_length;
        if (hit_t > ray.maxT()) {
            return false;
        }

        return true;
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
