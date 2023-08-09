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

            const data = self.tree.data.interpolateData(local_ray, hit.index, hit.u);

            const t = math.normalize3(trafo.objectToWorldNormal(data.dpdu));
            const b = math.normalize3(trafo.objectToWorldNormal(data.dpdv));
            const n = math.cross3(t, b);

            const geo_n = trafo.objectToWorldNormal(data.geo_n);

            isec.p = ray.point(hit.t);
            isec.t = t;
            isec.b = b;
            isec.n = n;
            isec.geo_n = geo_n;
            isec.uv = .{ hit.u, data.v };
            isec.offset = @fabs(data.v - 0.5) * data.width;
            isec.part = 0;
            isec.primitive = hit.index;

            return true;
        }

        return false;
    }

    pub fn intersectP(self: Mesh, ray: Ray, trafo: Trafo) bool {
        const local_ray = trafo.worldToObjectRay(ray);

        return self.tree.intersectP(local_ray);
    }

    pub fn visibility(self: Mesh, ray: Ray, trafo: Trafo) ?Vec4f {
        return if (self.intersectP(ray, trafo)) null else @splat(1.0);
    }
};
