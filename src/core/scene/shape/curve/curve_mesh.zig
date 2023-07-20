const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;

pub const Mesh = struct {
    pub fn intersect(self: Mesh, ray: *Ray, trafo: Trafo, isec: *Intersection) bool {
        const tray = trafo.worldToObjectRay(ray.*);
    }
};
