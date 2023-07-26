const curve = @import("curve.zig");
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const int = @import("../intersection.zig");
const Intersection = int.Intersection;
const Tree = @import("curve_tree.zig").Tree;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Mesh = struct {
    tree: Tree = .{},

    pub fn deinit(self: *Mesh, alloc: Allocator) void {
        self.tree.deinit(alloc);
    }

    pub fn intersect(self: Mesh, ray: *Ray, trafo: Trafo, isec: *Intersection) bool {
        var local_ray = trafo.worldToObjectRay(ray.*);

        if (self.tree.intersect(local_ray)) |hit| {
            ray.setMaxT(hit.t);

            const geo_n = trafo.objectToWorldNormal(hit.geo_n);
            const width = self.tree.data.curveWidth(hit.index, hit.u);

            isec.p = ray.point(hit.t) + @splat(4, @as(f32, 0.5) * width) * geo_n;

            const t = math.normalize3(trafo.objectToWorldNormal(hit.dpdu));
            const b = math.normalize3(trafo.objectToWorldNormal(hit.dpdv));
            const n = math.cross3(t, b);

            isec.part = 0;
            isec.primitive = 0;
            isec.t = t;
            isec.b = b;
            isec.n = n;
            isec.geo_n = geo_n;

            return true;
        }

        return false;
    }

    fn segmentBounds(self: Mesh, id: u32, points: [4]Vec4f, u_mima: Vec2f) AABB {
        var bounds = curve.cubicBezierBounds(points);

        const width0 = self.tree.data.widths[id * 2 + 0];
        const width1 = self.tree.data.widths[id * 2 + 1];

        const w0 = math.lerp(width0, width1, u_mima[0]);
        const w1 = math.lerp(width0, width1, u_mima[1]);

        bounds.expand(math.max(w0, w1) * 0.5);

        return bounds;
    }

    fn linearSegmentBounds(self: Mesh, id: u32, points: [4]Vec4f, u_mima: Vec2f) AABB {
        var bounds = AABB.init(math.min4(points[0], points[3]), math.max4(points[0], points[3]));

        const width0 = self.tree.data.widths[id * 2 + 0];
        const width1 = self.tree.data.widths[id * 2 + 1];

        const w0 = math.lerp(width0, width1, u_mima[0]);
        const w1 = math.lerp(width0, width1, u_mima[1]);

        bounds.expand(math.max(w0, w1) * 0.5);

        return bounds;
    }

    pub fn intersectP(self: Mesh, ray: Ray, trafo: Trafo) bool {
        const local_ray = trafo.worldToObjectRay(ray);

        return self.tree.intersectP(local_ray);
    }

    pub fn visibility(self: Mesh, ray: Ray, trafo: Trafo) ?Vec4f {
        return if (self.intersectP(ray, trafo)) null else @splat(4, @as(f32, 1.0));
    }
};
