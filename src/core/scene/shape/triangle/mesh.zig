const base = @import("base");
usingnamespace base;

//const Vec4f = base.math.Vec4f;
const Ray = base.math.Ray;

const Transformation = @import("../../composed_transformation.zig").Composed_transformation;
const Intersection = @import("../intersection.zig").Intersection;
const bvh = @import("bvh/tree.zig");

pub const Mesh = struct {
    tree: bvh.Tree,

    pub fn intersect(self: Mesh, ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        var tray = Ray.init(
            trafo.world_to_object.transformPoint(ray.origin),
            trafo.world_to_object.transformVector(ray.direction),
            ray.minT(),
            ray.maxT(),
        );

        if (self.tree.intersect(&tray)) |hit| {
            ray.setMaxT(tray.maxT());

            const p = self.tree.data.interpolateP(hit.u, hit.v, hit.index);

            isec.p = trafo.objectToWorldPoint(p);

            return true;
        }

        return false;
    }

    pub fn intersectP(self: Mesh, ray: Ray, trafo: Transformation) bool {
        var tray = Ray.init(
            trafo.world_to_object.transformPoint(ray.origin),
            trafo.world_to_object.transformVector(ray.direction),
            ray.minT(),
            ray.maxT(),
        );

        return self.tree.intersectP(tray);
    }
};
