const Ray = @import("../ray.zig").Ray;
const Material = @import("../material/material.zig").Material;
const Scene = @import("../scene.zig").Scene;
const Worker = @import("../worker.zig").Worker;
const shp = @import("../shape/intersection.zig");

const base = @import("base");
usingnamespace base;

pub const Null = 0xFFFFFFFF;

pub const Prop = struct {
    shape: u32 = Null,

    is_complex: bool = false,

    pub fn configure(self: *Prop, shape: u32, materials: []u32, scene: Scene) void {
        self.shape = shape;

        self.is_complex = scene.shape(shape).isComplex();

        _ = materials;
    }

    pub fn intersect(
        self: Prop,
        entity: usize,
        ray: *Ray,
        worker: *Worker,
        isec: *shp.Intersection,
    ) bool {
        const scene = worker.scene;

        if (self.is_complex and !scene.propAabbIntersectP(entity, ray.*)) {
            return false;
        }

        const trafo = scene.propTransformationAt(entity);

        return scene.propShape(entity).intersect(ray, trafo, worker, isec);
    }

    pub fn intersectP(
        self: Prop,
        entity: usize,
        ray: Ray,
        worker: *Worker,
    ) bool {
        const scene = worker.scene;

        if (self.is_complex and !scene.propAabbIntersectP(entity, ray)) {
            return false;
        }

        const trafo = scene.propTransformationAt(entity);

        return scene.propShape(entity).intersectP(ray, trafo, worker);
    }
};
