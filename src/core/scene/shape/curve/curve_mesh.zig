const curve = @import("curve.zig");
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const int = @import("../intersection.zig");
const Intersection = int.Intersection;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
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
            .{ -0.5, 0.33, 0.0, 0.0 },
            .{ 0.5, 0.66, 0.0, 0.0 },
            .{ 0.0, 1.0, 0.0, 0.0 },
        };

        const width: [2]f32 = .{ 0.2, 0.1 };

        const bounds = curve.cubicBezierBounds(points);

        return .{ .points = points, .width = width, .aabb = bounds };
    }

    pub fn intersect(self: Mesh, ray: *Ray, trafo: Trafo, isec: *Intersection) bool {
        const local_ray = trafo.worldToObjectRay(ray.*);

        const hit_t = self.aabb.intersectP(local_ray) orelse return false;
        if (hit_t > ray.maxT()) {
            return false;
        }

        ray.setMaxT(hit_t);

        isec.p = ray.point(hit_t);

        const local_p = local_ray.point(hit_t);
        const distance = @fabs(@splat(4, @as(f32, 1.0)) - @fabs(local_p));

        const i = math.indexMinComponent3(distance);
        const s = std.math.copysign(@as(f32, 1.0), local_p[i]);
        const n = @splat(4, s) * trafo.rotation.r[i];

        isec.part = 0;
        isec.primitive = 0;
        isec.geo_n = n;
        isec.n = n;

        return true;
    }

    pub fn intersectP(self: Mesh, ray: Ray, trafo: Trafo) bool {
        const local_ray = trafo.worldToObjectRay(ray);

        return self.aabb.intersect(local_ray);
    }

    pub fn visibility(self: Mesh, ray: Ray, trafo: Trafo) ?Vec4f {
        return if (self.intersectP(ray, trafo)) null else @splat(4, @as(f32, 1.0));
    }
};
