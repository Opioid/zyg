const curve = @import("curve.zig");
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const int = @import("../intersection.zig");
const Intersection = int.Intersection;
const Fragment = @import("../intersection.zig").Fragment;
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

    pub fn intersect(self: *const Mesh, ray: Ray, trafo: Trafo) Intersection {
        const local_ray = trafo.worldToObjectRay(ray);
        return self.tree.intersect(local_ray);
    }

    pub fn fragment(self: *const Mesh, ray: Ray, frag: *Fragment) void {
        const local_ray = frag.trafo.worldToObjectRay(ray);

        const hit_u = frag.isec.u;

        const data = self.tree.data.interpolateData(local_ray, frag.isec.primitive, hit_u);

        const t = math.normalize3(frag.trafo.objectToWorldNormal(data.dpdu));
        const b = math.normalize3(frag.trafo.objectToWorldNormal(data.dpdv));
        const n = math.cross3(t, b);

        const geo_n = frag.trafo.objectToWorldNormal(data.geo_n);

        const offset = frag.trafo.scaleX() * 0.5 * data.width;

        frag.p = ray.point(ray.maxT());
        frag.t = t;
        frag.b = b;
        frag.n = n;
        frag.geo_n = geo_n;
        frag.uvw = .{ hit_u, data.v, 0.0, offset };
        frag.part = 0;
    }

    pub fn intersectP(self: *const Mesh, ray: Ray, trafo: Trafo) bool {
        const local_ray = trafo.worldToObjectRay(ray);
        return self.tree.intersectP(local_ray);
    }

    pub fn visibility(self: *const Mesh, ray: Ray, trafo: Trafo, tr: *Vec4f) bool {
        _ = tr;

        if (self.intersectP(ray, trafo)) {
            return false;
        }

        return true;
    }
};
