const Ray = @import("../ray.zig").Ray;
const Material = @import("../material/material.zig").Material;
const Filter = @import("../../image/texture/texture_sampler.zig").Filter;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Scene = @import("../scene.zig").Scene;
const shp = @import("../shape/intersection.zig");
const Worker = @import("../../rendering/worker.zig").Worker;

const base = @import("base");
const Vec4f = base.math.Vec4f;

pub const Prop = struct {
    pub const Null: u32 = 0xFFFFFFFF;

    const Properties = packed struct {
        visible_in_camera: bool = true,
        visible_in_reflection: bool = true,
        visible_in_shadow: bool = true,
        evaluate_visibility: bool = false,
        caustic: bool = false,
        test_AABB: bool = false,
        static: bool = true,
    };

    shape: u32 = Null,

    properties: Properties = .{},

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

    pub fn evaluateVisibility(self: Prop) bool {
        return self.properties.evaluate_visibility;
    }

    pub fn caustic(self: Prop) bool {
        return self.properties.caustic;
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

        const shape_inst = scene.shape(shape);
        self.properties.test_AABB = shape_inst.finite() and shape_inst.complex();

        for (materials) |mid| {
            const m = scene.material(mid);
            if (m.evaluateVisibility()) {
                self.properties.evaluate_visibility = true;
            }

            if (m.caustic()) {
                self.properties.caustic = true;
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
        entity: u32,
        ray: *Ray,
        scene: *const Scene,
        ipo: shp.Interpolation,
        isec: *shp.Intersection,
    ) bool {
        if (!self.visible(ray.depth)) {
            return false;
        }

        if (self.properties.test_AABB and !scene.propAabbIntersect(entity, ray.*)) {
            return false;
        }

        const static = self.properties.static;
        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, static);

        if (scene.shape(self.shape).intersect(ray, trafo, ipo, isec)) {
            isec.trafo = trafo;
            return true;
        }

        return false;
    }

    pub fn intersectShadow(self: Prop, entity: u32, ray: *Ray, scene: *const Scene, isec: *shp.Intersection) bool {
        const properties = self.properties;

        if (!properties.visible_in_shadow) {
            return false;
        }

        if (properties.test_AABB and !scene.propAabbIntersect(entity, ray.*)) {
            return false;
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, properties.static);

        return scene.shape(self.shape).intersect(ray, trafo, .Normal, isec);
    }

    pub fn intersectP(self: Prop, entity: u32, ray: Ray, scene: *const Scene) bool {
        const properties = self.properties;

        if (!properties.visible_in_shadow) {
            return false;
        }

        if (properties.test_AABB and !scene.propAabbIntersect(entity, ray)) {
            return false;
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, properties.static);

        return scene.shape(self.shape).intersectP(ray, trafo);
    }

    pub fn visibility(self: Prop, entity: u32, ray: Ray, filter: ?Filter, scene: *const Scene) ?Vec4f {
        const properties = self.properties;

        if (!properties.evaluate_visibility) {
            if (self.intersectP(entity, ray, scene)) {
                return null;
            }

            return @splat(4, @as(f32, 1.0));
        }

        if (!properties.visible_in_shadow) {
            return @splat(4, @as(f32, 1.0));
        }

        if (properties.test_AABB and !scene.propAabbIntersect(entity, ray)) {
            return @splat(4, @as(f32, 1.0));
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, properties.static);

        return scene.shape(self.shape).visibility(ray, trafo, entity, filter, scene);
    }

    pub fn transmittance(self: Prop, entity: u32, ray: Ray, filter: ?Filter, worker: *Worker) ?Vec4f {
        const properties = self.properties;
        const scene = worker.scene;

        if (properties.test_AABB and !scene.propAabbIntersect(entity, ray)) {
            return @splat(4, @as(f32, 1.0));
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, properties.static);

        return scene.shape(self.shape).transmittance(ray, trafo, entity, filter, worker);
    }

    pub fn scatter(
        self: Prop,
        entity: u32,
        ray: *Ray,
        throughput: Vec4f,
        filter: ?Filter,
        sampler: *Sampler,
        worker: *Worker,
    ) shp.Result {
        const properties = self.properties;
        const scene = worker.scene;

        if (properties.test_AABB and !scene.propAabbIntersect(entity, ray.*)) {
            return shp.Result.initPass(@splat(4, @as(f32, 1.0)));
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, properties.static);

        return scene.shape(self.shape).scatter(ray, trafo, throughput, entity, filter, sampler, worker);
    }
};
