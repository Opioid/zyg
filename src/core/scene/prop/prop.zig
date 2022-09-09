const Ray = @import("../ray.zig").Ray;
const Material = @import("../material/material.zig").Material;
const Filter = @import("../../image/texture/sampler.zig").Filter;
const Scene = @import("../scene.zig").Scene;
const Worker = @import("../worker.zig").Worker;
const shp = @import("../shape/intersection.zig");

const base = @import("base");
const Vec4f = base.math.Vec4f;

pub const Prop = struct {
    pub const Null: u32 = 0xFFFFFFFF;

    const Properties = packed struct {
        visible_in_camera: bool = false,
        visible_in_reflection: bool = false,
        visible_in_shadow: bool = false,
        tinted_shadow: bool = false,
        test_AABB: bool = false,
        static: bool = false,
    };

    shape: u32 = Null,

    properties: Properties = undefined,

    fn visible(self: Prop, ray_depth: u32) bool {
        if (0 == ray_depth) {
            return self.properties.visible_in_camera;
        }

        return self.properties.visible_in_reflection;
    }

    pub fn visibleInCamera(self: Prop) bool {
        return self.properties.visible_in_camera;
    }

    pub fn visibleInReflection(self: Prop) bool {
        return self.properties.visible_in_reflection;
    }

    pub fn visibleInShadow(self: Prop) bool {
        return self.properties.visible_in_shadow;
    }

    pub fn tintedShadow(self: Prop) bool {
        return self.properties.tinted_shadow;
    }

    pub fn setVisibleInShadow(self: *Prop, value: bool) void {
        self.properties.visible_in_shadow = value;
    }

    pub fn setVisibility(self: *Prop, in_camera: bool, in_reflection: bool, in_shadow: bool) void {
        self.properties.visible_in_camera = in_camera;
        self.properties.visible_in_reflection = in_reflection;
        self.properties.visible_in_shadow = in_shadow;
    }

    pub fn configure(self: *Prop, shape: u32, materials: []const u32, scene: *const Scene) void {
        self.shape = shape;

        self.properties = Properties{};
        self.properties.visible_in_camera = true;
        self.properties.visible_in_reflection = true;
        self.properties.visible_in_shadow = true;

        const shape_inst = scene.shape(shape);
        self.properties.test_AABB = shape_inst.finite() and shape_inst.complex();

        self.properties.static = true;

        for (materials) |mid| {
            const m = scene.material(mid);

            if (m.masked() or m.tintedShadow()) {
                self.properties.tinted_shadow = true;
                break;
            }
        }
    }

    pub fn configureAnimated(self: *Prop, scene: *const Scene) void {
        const shape_inst = scene.shape(self.shape);

        self.properties.test_AABB = shape_inst.finite();
        self.properties.static = false;
    }

    pub fn intersect(
        self: Prop,
        entity: usize,
        ray: *Ray,
        worker: *Worker,
        ipo: shp.Interpolation,
        isec: *shp.Intersection,
    ) bool {
        if (!self.visible(ray.depth)) {
            return false;
        }

        const scene = worker.scene;

        if (self.properties.test_AABB and !scene.propAabbIntersect(entity, ray)) {
            return false;
        }

        const static = self.properties.static;
        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, static);

        if (scene.propShape(entity).intersect(ray, trafo, ipo, isec)) {
            isec.trafo = trafo;
            return true;
        }

        return false;
    }

    pub fn intersectShadow(
        self: Prop,
        entity: usize,
        ray: *Ray,
        worker: *Worker,
        isec: *shp.Intersection,
    ) bool {
        if (!self.visibleInShadow()) {
            return false;
        }

        const scene = worker.scene;

        if (self.properties.test_AABB and !scene.propAabbIntersect(entity, ray)) {
            return false;
        }

        const static = self.properties.static;
        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, static);

        return scene.propShape(entity).intersect(ray, trafo, .Normal, isec);
    }

    pub fn intersectP(
        self: Prop,
        entity: usize,
        ray: *const Ray,
        worker: *Worker,
    ) bool {
        if (!self.visibleInShadow()) {
            return false;
        }

        const scene = worker.scene;

        if (self.properties.test_AABB and !scene.propAabbIntersect(entity, ray)) {
            return false;
        }

        const static = self.properties.static;
        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, static);

        return scene.propShape(entity).intersectP(ray, trafo);
    }

    pub fn visibility(self: Prop, entity: usize, ray: *const Ray, filter: ?Filter, worker: *Worker) ?Vec4f {
        if (!self.tintedShadow()) {
            if (self.intersectP(entity, ray, worker)) {
                return null;
            }

            return @splat(4, @as(f32, 1.0));
        }

        if (!self.visibleInShadow()) {
            return @splat(4, @as(f32, 1.0));
        }

        const scene = worker.scene;

        if (self.properties.test_AABB and !scene.propAabbIntersect(entity, ray)) {
            return @splat(4, @as(f32, 1.0));
        }

        const static = self.properties.static;
        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, static);

        return scene.propShape(entity).visibility(ray, trafo, entity, filter, worker);
    }
};
