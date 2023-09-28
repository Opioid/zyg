const Intersector = @import("../vertex.zig").Vertex.Intersector;
const Material = @import("../material/material.zig").Material;
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
        volume: bool = false,
        caustic: bool = false,
        test_AABB: bool = false,
        static: bool = true,
    };

    shape: u32 = Null,

    properties: Properties = .{},

    fn visible(self: Prop, ray_depth: u32) bool {
        const properties = self.properties;

        if (properties.volume) {
            return false;
        }

        if (0 == ray_depth) {
            return properties.visible_in_camera;
        }

        return properties.visible_in_reflection;
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

    pub fn volume(self: Prop) bool {
        return self.properties.volume;
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

        var mono = true;

        if (materials.len > 0) {
            const mid0 = materials[0];

            for (materials) |mid| {
                const m = scene.material(mid);
                if (m.evaluateVisibility()) {
                    self.properties.evaluate_visibility = true;
                }

                if (m.caustic()) {
                    self.properties.caustic = true;
                }

                if (mid != mid0) {
                    mono = false;
                }
            }
        }

        self.properties.volume = shape_inst.finite() and mono and 1.0 == scene.material(materials[0]).ior();
    }

    pub fn configureAnimated(self: *Prop, scene: *const Scene) void {
        const shape_inst = scene.shape(self.shape);
        self.properties.test_AABB = shape_inst.finite();
        self.properties.static = false;
    }

    pub fn intersect(
        self: Prop,
        entity: u32,
        isec: *Intersector,
        scene: *const Scene,
        ipo: shp.Interpolation,
    ) bool {
        if (!self.visible(isec.depth)) {
            return false;
        }

        if (self.properties.test_AABB and !scene.propAabbIntersect(entity, isec.ray)) {
            return false;
        }

        const static = self.properties.static;
        const trafo = scene.propTransformationAtMaybeStatic(entity, isec.time, static);

        if (scene.shape(self.shape).intersect(&isec.ray, trafo, ipo, &isec.hit)) {
            isec.hit.trafo = trafo;
            return true;
        }

        return false;
    }

    pub fn intersectSSS(self: Prop, entity: u32, isec: *Intersector, scene: *const Scene) bool {
        const properties = self.properties;

        if (!properties.visible_in_shadow) {
            return false;
        }

        if (properties.test_AABB and !scene.propAabbIntersect(entity, isec.ray)) {
            return false;
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, isec.time, properties.static);

        return scene.shape(self.shape).intersect(&isec.ray, trafo, .Normal, &isec.hit);
    }

    pub fn intersectP(self: Prop, entity: u32, isec: *const Intersector, scene: *const Scene) bool {
        const properties = self.properties;

        if (!properties.visible_in_shadow) {
            return false;
        }

        if (properties.test_AABB and !scene.propAabbIntersect(entity, isec.ray)) {
            return false;
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, isec.time, properties.static);

        return scene.shape(self.shape).intersectP(isec.ray, trafo);
    }

    pub fn visibility(self: Prop, entity: u32, isec: *const Intersector, sampler: *Sampler, worker: *Worker) ?Vec4f {
        const properties = self.properties;
        const scene = worker.scene;

        if (!properties.evaluate_visibility) {
            if (self.intersectP(entity, isec, scene)) {
                return null;
            }

            return @as(Vec4f, @splat(1.0));
        }

        if (!properties.visible_in_shadow) {
            return @as(Vec4f, @splat(1.0));
        }

        if (properties.test_AABB and !scene.propAabbIntersect(entity, isec.ray)) {
            return @as(Vec4f, @splat(1.0));
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, isec.time, properties.static);

        if (properties.volume) {
            return scene.shape(self.shape).transmittance(isec.ray, isec.depth, trafo, entity, sampler, worker);
        } else {
            return scene.shape(self.shape).visibility(isec.ray, trafo, entity, sampler, scene);
        }
    }

    pub fn scatter(
        self: Prop,
        entity: u32,
        isec: *const Intersector,
        throughput: Vec4f,
        sampler: *Sampler,
        worker: *Worker,
    ) shp.Volume {
        const properties = self.properties;
        const scene = worker.scene;

        if (properties.test_AABB and !scene.propAabbIntersect(entity, isec.ray)) {
            return shp.Volume.initPass(@splat(1.0));
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, isec.time, properties.static);

        return scene.shape(self.shape).scatter(isec.ray, isec.depth, trafo, throughput, entity, sampler, worker);
    }
};
