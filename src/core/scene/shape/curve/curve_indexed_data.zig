const CurveBuffer = @import("curve_buffer.zig").Buffer;
const curve = @import("curve.zig");
const IndexCurve = curve.IndexCurve;

const math = @import("base").math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Mat2x3 = math.Mat2x3;
const Mat4x4 = math.Mat4x4;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const IndexedData = struct {
    pub const Segment = struct {
        p: u32,
        w: u32,
    };

    pub const Intersection = struct {
        t: f32 = undefined,
        u: f32 = undefined,
    };

    pub const Data = struct {
        geo_n: Vec4f = undefined,
        dpdu: Vec4f = undefined,
        dpdv: Vec4f = undefined,
        v: f32 = undefined,
        width: f32 = undefined,
    };

    num_indices: u32 = 0,

    num_points: u32 = 0,
    num_widths: u32 = 0,

    indices: [*]Segment = undefined,
    partitions: [*]u8 = undefined,
    points: [*]f32 = undefined,
    widths: [*]f32 = undefined,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.widths[0..self.num_widths]);
        alloc.free(self.points[0 .. self.num_points * 3 + 1]);
        alloc.free(self.partitions[0..self.num_indices]);
        alloc.free(self.indices[0..self.num_indices]);
    }

    pub fn allocateCurves(self: *Self, alloc: Allocator, num_indices: u32, curves: CurveBuffer) !void {
        self.num_indices = num_indices;

        const num_points = curves.numPoints();
        const num_widths = curves.numWidths();
        self.num_points = num_points;
        self.num_widths = num_widths;

        self.indices = (try alloc.alloc(Segment, num_indices)).ptr;
        self.partitions = (try alloc.alloc(u8, num_indices)).ptr;

        self.points = (try alloc.alloc(f32, num_points * 3 + 1)).ptr;
        self.widths = (try alloc.alloc(f32, num_widths)).ptr;

        curves.copy(self.points, self.widths);
        self.points[num_points * 3] = 0.0;
    }

    pub fn setCurve(self: *Self, curve_id: u32, index: IndexCurve, partition: u8) void {
        self.indices[curve_id] = .{ .p = index.pos, .w = index.width };
        self.partitions[curve_id] = partition;
    }

    const Partition = struct {
        cp: [4]Vec4f,
        u_range: Vec2f,
    };

    fn curvePartition(cp: [4]Vec4f, p: u32) Partition {
        if (1 == p) {
            return .{
                .cp = curve.cubicBezierSubdivide4_0(cp),
                .u_range = .{ 0.0, 0.25 },
            };
        } else if (2 == p) {
            return .{
                .cp = curve.cubicBezierSubdivide4_1(cp),
                .u_range = .{ 0.25, 0.5 },
            };
        } else if (3 == p) {
            return .{
                .cp = curve.cubicBezierSubdivide4_2(cp),
                .u_range = .{ 0.5, 0.75 },
            };
        } else if (4 == p) {
            return .{
                .cp = curve.cubicBezierSubdivide4_3(cp),
                .u_range = .{ 0.75, 1.0 },
            };
        }

        return .{ .cp = cp, .u_range = .{ 0.0, 1.0 } };
    }

    pub fn intersect(self: *const Self, ray: Ray, id: u32) ?Intersection {
        const index = self.indices[id];

        const partition = curvePartition(self.curvePoints(index.p), self.partitions[id]);
        const width = Vec2f{ self.widths[index.w + 0], self.widths[index.w + 1] };

        const depth = refinementDepth(partition.cp, width, partition.u_range);

        var dx = math.cross3(ray.direction, partition.cp[3] - partition.cp[0]);
        if (0.0 == math.squaredLength3(dx)) {
            dx = math.tangent3(ray.direction);
        }

        const ray_to_object = math.Mat4x4.initLookAt(ray.origin, ray.direction, dx);

        const cpr: [4]Vec4f = .{
            ray_to_object.transformPointTransposed(partition.cp[0]),
            ray_to_object.transformPointTransposed(partition.cp[1]),
            ray_to_object.transformPointTransposed(partition.cp[2]),
            ray_to_object.transformPointTransposed(partition.cp[3]),
        };

        return recursiveIntersectSegment(ray, cpr, width, partition.u_range, depth);
    }

    pub fn intersectP(self: *const Self, ray: Ray, id: u32) bool {
        const index = self.indices[id];

        const partition = curvePartition(self.curvePoints(index.p), self.partitions[id]);
        const width = Vec2f{ self.widths[index.w + 0], self.widths[index.w + 1] };

        const depth = refinementDepth(partition.cp, width, partition.u_range);

        var dx = math.cross3(ray.direction, partition.cp[3] - partition.cp[0]);
        if (0.0 == math.squaredLength3(dx)) {
            dx = math.tangent3(ray.direction);
        }

        const ray_to_object = math.Mat4x4.initLookAt(ray.origin, ray.direction, dx);

        const cpr: [4]Vec4f = .{
            ray_to_object.transformPointTransposed(partition.cp[0]),
            ray_to_object.transformPointTransposed(partition.cp[1]),
            ray_to_object.transformPointTransposed(partition.cp[2]),
            ray_to_object.transformPointTransposed(partition.cp[3]),
        };

        return recursiveIntersectSegmentP(ray, cpr, width, partition.u_range, depth);
    }

    pub fn interpolateData(self: *const Self, ray: Ray, id: u32, u: f32) Data {
        const index = self.indices[id];

        const cp = self.curvePoints(index.p);

        const partition = curvePartition(cp, self.partitions[id]);

        var dx = math.cross3(ray.direction, partition.cp[3] - partition.cp[0]);
        if (0.0 == math.squaredLength3(dx)) {
            dx = math.tangent3(ray.direction);
        }

        const ray_to_object = math.Mat4x4.initLookAt(ray.origin, ray.direction, dx);

        const dpdu = curve.cubicBezierEvaluateDerivative(cp, u);

        const width = Vec2f{ self.widths[index.w + 0], self.widths[index.w + 1] };
        const hit_width = math.lerp(width[0], width[1], u);

        const dpdu_plane = ray_to_object.transformVectorTransposed(dpdu);
        var dpdv_plane = math.normalize3(Vec4f{ -dpdu_plane[1], dpdu_plane[0], 0.0, 0.0 }) * @as(Vec4f, @splat(hit_width));

        const geo_n = math.normalize3(math.cross3(ray_to_object.transformVector(dpdv_plane), dpdu));

        const cpr: [4]Vec4f = .{
            ray_to_object.transformPointTransposed(cp[0]),
            ray_to_object.transformPointTransposed(cp[1]),
            ray_to_object.transformPointTransposed(cp[2]),
            ray_to_object.transformPointTransposed(cp[3]),
        };

        const eval = curve.cubicBezierEvaluateWithDerivative(cpr, u);
        const pc = eval[0];
        const dpcdw = eval[1];

        const pt_curve_dist = @sqrt(pc[0] * pc[0] + pc[1] * pc[1]);
        const edge_func = pc[1] * -dpcdw[0] + pc[0] * dpcdw[1];
        const v = if (edge_func > 0.0) 0.5 + pt_curve_dist / hit_width else 0.5 - pt_curve_dist / hit_width;

        // {
        //     // Rotate dpdv_plane to give cylindrical appearance
        //     const theta = math.lerp(-0.5 * std.math.pi, 0.5 * std.math.pi, v);
        //     const rot = Mat2x3.initRotation(dpdu_plane, theta);
        //     dpdv_plane = rot.transformVector(dpdv_plane);
        // }

        const dpdv = ray_to_object.transformVector(dpdv_plane);

        return .{
            .geo_n = geo_n,
            .dpdu = dpdu,
            .dpdv = dpdv,
            .v = v,
            .width = hit_width,
        };
    }

    fn recursiveIntersectSegment(
        ray: Ray,
        cp: [4]Vec4f,
        width: Vec2f,
        u_range: Vec2f,
        depth: u32,
    ) ?Intersection {
        const curve_bounds = segmentBounds(cp, width, u_range);
        const ray_bounds = AABB.init(@splat(0.0), .{ 0.0, 0.0, math.length3(ray.direction) * ray.maxT(), 0.0 });
        if (!curve_bounds.overlaps(ray_bounds)) {
            return null;
        }

        if (0 == depth) {
            return intersectSegment(ray, cp, width, u_range);
        }

        const segments = curve.cubicBezierSubdivide(cp);

        var tray = ray;

        const u_middle = 0.5 * (u_range[0] + u_range[1]);
        const next_depth = depth - 1;

        const hit0 = recursiveIntersectSegment(tray, segments[0..4].*, width, .{ u_range[0], u_middle }, next_depth);
        if (hit0) |hit| {
            tray.setMaxT(hit.t);
        }

        if (recursiveIntersectSegment(tray, segments[3..7].*, width, .{ u_middle, u_range[1] }, next_depth)) |hit| {
            return hit;
        }

        return hit0;
    }

    fn intersectSegment(ray: Ray, cp: [4]Vec4f, width: Vec2f, u_range: Vec2f) ?Intersection {
        if (!testTangents(cp)) {
            return null;
        }

        // Find line w that gives minimum distance to sample point
        const segment_dir = Vec2f{ cp[3][0], cp[3][1] } - Vec2f{ cp[0][0], cp[0][1] };
        const denom = math.squaredLength2(segment_dir);
        if (0.0 == denom) {
            return null;
        }

        const w = math.dot2(-Vec2f{ cp[0][0], cp[0][1] }, segment_dir) / denom;

        // Compute u coordinate of curve intersection point and _hitWidth_
        const u = math.clamp(math.lerp(u_range[0], u_range[1], w), u_range[0], u_range[1]);

        const hit_width = math.lerp(width[0], width[1], u);

        const pc = curve.cubicBezierEvaluate(cp, math.clamp(w, 0.0, 1.0));

        const pt_curve_dist2 = pc[0] * pc[0] + pc[1] * pc[1];
        if (pt_curve_dist2 > (hit_width * hit_width) * 0.25) {
            return null;
        }

        const ray_length = math.length3(ray.direction);
        if (pc[2] < 0.0 or pc[2] > ray_length * ray.maxT()) {
            return null;
        }

        const hit_t = pc[2] / ray_length;
        if (hit_t > ray.maxT()) {
            return null;
        }

        return .{ .t = hit_t, .u = u };
    }

    fn recursiveIntersectSegmentP(ray: Ray, cp: [4]Vec4f, width: Vec2f, u_range: Vec2f, depth: u32) bool {
        const curve_bounds = segmentBounds(cp, width, u_range);
        const ray_bounds = AABB.init(@splat(0.0), .{ 0.0, 0.0, math.length3(ray.direction) * ray.maxT(), 0.0 });
        if (!curve_bounds.overlaps(ray_bounds)) {
            return false;
        }

        if (0 == depth) {
            return intersectSegmentP(ray, cp, width, u_range);
        }

        const segments = curve.cubicBezierSubdivide(cp);

        const u_middle = 0.5 * (u_range[0] + u_range[1]);
        const next_depth = depth - 1;

        if (recursiveIntersectSegmentP(ray, segments[0..4].*, width, .{ u_range[0], u_middle }, next_depth)) {
            return true;
        }

        return recursiveIntersectSegmentP(ray, segments[3..7].*, width, .{ u_middle, u_range[1] }, next_depth);
    }

    fn intersectSegmentP(ray: Ray, cp: [4]Vec4f, width: Vec2f, u_range: Vec2f) bool {
        if (!testTangents(cp)) {
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

        const hit_width = math.lerp(width[0], width[1], u);

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

    fn segmentBounds(cp: [4]Vec4f, width: Vec2f, u_range: Vec2f) AABB {
        var box = curve.cubicBezierBounds(cp);
        const w0 = math.lerp(width[0], width[1], u_range[0]);
        const w1 = math.lerp(width[0], width[1], u_range[1]);
        box.expand(math.max(w0, w1) * 0.5);
        return box;
    }

    inline fn curvePoints(self: *const Self, index: u32) [4]Vec4f {
        const offset = index * 3;

        return .{
            self.points[offset + 0 ..][0..4].*,
            self.points[offset + 3 ..][0..4].*,
            self.points[offset + 6 ..][0..4].*,
            self.points[offset + 9 ..][0..4].*,
        };
    }

    inline fn testTangents(cp: [4]Vec4f) bool {
        // Test sample point against tangent perpendicular at curve start
        const edge0 = -cp[0][1] * (cp[1][1] - cp[0][1]) + cp[0][0] * (cp[0][0] - cp[1][0]);
        if (edge0 < 0.0) {
            return false;
        }

        // Test sample point against tangent perpendicular at curve end
        const edge1 = -cp[3][1] * (cp[2][1] - cp[3][1]) + cp[3][0] * (cp[3][0] - cp[2][0]);
        if (edge1 < 0.0) {
            return false;
        }

        return true;
    }

    fn refinementDepth(cp: [4]Vec4f, width: Vec2f, u_range: Vec2f) u32 {
        var l: f32 = 0.0;
        for (0..2) |i| {
            const v = @fabs(cp[i] - @as(Vec4f, @splat(2.0)) * cp[i + 1] + cp[i + 2]);
            l = math.max(l, math.hmax3(v));
        }

        if (l > 0.0) {
            const w0 = math.lerp(width[0], width[1], u_range[0]);
            const w1 = math.lerp(width[0], width[1], u_range[1]);
            const eps = math.max(w0, w1) * 0.05; // width / 20
            // Compute log base 4 by dividing log2 in half.
            const r0 = @divTrunc(log2int(1.41421356237 * 6.0 * l / (8.0 * eps)), 2);
            return @intCast(std.math.clamp(@as(i32, @intCast(r0)), 0, 10));
        }

        return 0;
    }

    inline fn exponent(v: f32) i32 {
        return (@as(i32, @bitCast(v)) >> 23) - 127;
    }

    inline fn significand(v: f32) i32 {
        return @as(i32, @bitCast(v)) & ((1 << 23) - 1);
    }

    fn log2int(v: f32) i32 {
        if (v < 1.0) {
            return -log2int(1.0 / v);
        }

        const midsignif = 0b00000000001101010000010011110011;
        return exponent(v) + @as(i32, if (significand(v) >= midsignif) 1 else 0);
    }
};
