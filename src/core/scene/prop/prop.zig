const Ray = @import("../ray.zig").Ray;
const Scene = @import("../scene.zig").Scene;
const shp = @import("../shape/intersection.zig");

const base = @import("base");
usingnamespace base;

pub const Null = 0xFFFFFFFF;

pub const Prop = struct {
    shape: u32 = Null,

    is_complex: bool = false,

    pub fn configure(self: *Prop, shape: u32, scene: Scene) void {
        self.shape = shape;

        self.is_complex = scene.shape(shape).isComplex();
    }

    pub fn intersect(
        self: Prop,
        entity: usize,
        ray: *Ray,
        scene: Scene,
        isec: *shp.Intersection,
    ) bool {
        if (self.is_complex and !scene.propAabbIntersectP(entity, ray.*)) {
            return false;
        }

        const trafo = scene.propTransformationAt(entity);

        return scene.propShape(entity).intersect(&ray.ray, trafo, isec);
    }

    pub fn intersectP(self: Prop, entity: usize, ray: Ray, scene: Scene) bool {
        if (self.is_complex and !scene.propAabbIntersectP(entity, ray)) {
            return false;
        }

        const trafo = scene.propTransformationAt(entity);

        return scene.propShape(entity).intersectP(ray.ray, trafo);
    }
};
