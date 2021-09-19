const Ray = @import("../ray.zig").Ray;
const Material = @import("../material/material.zig").Material;
const Filter = @import("../../image/texture/sampler.zig").Filter;
const Scene = @import("../scene.zig").Scene;
const Worker = @import("../worker.zig").Worker;
const shp = @import("../shape/intersection.zig");
const base = @import("base");
const Vec4f = base.math.Vec4f;
const Flags = base.flags.Flags;
//usingnamespace base;

pub const Null = 0xFFFFFFFF;

pub const Prop = struct {
    const Property = enum(u32) {
        Visible_in_camera = 1 << 0,
        Test_AABB = 1 << 1,
        Tinted_shadow = 1 << 2,
    };

    shape: u32 = Null,

    properties: Flags(Property) = undefined,

    pub fn hasTintedShadow(self: Prop) bool {
        return self.properties.is(.Tinted_shadow);
    }

    pub fn configure(self: *Prop, shape: u32, materials: []u32, scene: Scene) void {
        self.shape = shape;

        self.properties.clear();
        self.properties.set(.Visible_in_camera, true);

        const shape_ptr = scene.shape(shape);
        self.properties.set(.Test_AABB, shape_ptr.isFinite() and shape_ptr.isComplex());

        for (materials) |mid| {
            const m = scene.material(mid);

            if (m.isMasked()) {
                self.properties.set(.Tinted_shadow, true);
            }
        }
    }

    pub fn intersect(
        self: Prop,
        entity: usize,
        ray: *Ray,
        worker: *Worker,
        isec: *shp.Intersection,
    ) bool {
        const scene = worker.scene;

        if (self.properties.is(.Test_AABB) and !scene.propAabbIntersectP(entity, ray.*)) {
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

        if (self.properties.is(.Test_AABB) and !scene.propAabbIntersectP(entity, ray)) {
            return false;
        }

        const trafo = scene.propTransformationAt(entity);

        return scene.propShape(entity).intersectP(ray, trafo, worker);
    }

    pub fn visibility(self: Prop, entity: usize, ray: Ray, filter: ?Filter, worker: *Worker, v: *Vec4f) bool {
        if (!self.hasTintedShadow()) {
            const ip = self.intersectP(entity, ray, worker);
            v.* = @splat(4, @as(f32, if (ip) 0.0 else 1.0));
            return !ip;
        }

        const scene = worker.scene;

        if (self.properties.is(.Test_AABB) and !scene.propAabbIntersectP(entity, ray)) {
            return false;
        }

        const trafo = scene.propTransformationAt(entity);
        return scene.propShape(entity).visibility(ray, trafo, entity, filter, worker, v);
    }
};
