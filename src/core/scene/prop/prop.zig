const Ray = @import("../ray.zig").Ray;
const Material = @import("../material/material.zig").Material;
const Filter = @import("../../image/texture/sampler.zig").Filter;
const Scene = @import("../scene.zig").Scene;
const Worker = @import("../worker.zig").Worker;
const shp = @import("../shape/intersection.zig");
const base = @import("base");
const Vec4f = base.math.Vec4f;
const Flags = base.flags.Flags;

pub const Prop = struct {
    pub const Null: u32 = 0xFFFFFFFF;

    pub const Topology = struct {
        next: u32 = Null,
        child: u32 = Null,
    };

    const Property = enum(u32) {
        VisibleInCamera = 1 << 0,
        VisibleInReflection = 1 << 1,
        VisibleInShadow = 1 << 2,
        TintedShadow = 1 << 3,
        TestAABB = 1 << 4,
        HasParent = 1 << 5,
        Static = 1 << 6,
        LocalAnimation = 1 << 7,
    };

    shape: u32 = Null,

    properties: Flags(Property) = undefined,

    fn visible(self: Prop, ray_depth: u32) bool {
        if (0 == ray_depth) {
            return self.properties.is(.VisibleInCamera);
        }

        return self.properties.is(.VisibleInReflection);
    }

    pub fn hasLocalAnimation(self: Prop) bool {
        return self.properties.is(.LocalAnimation);
    }

    pub fn noParent(self: Prop) bool {
        return self.properties.no(.HasParent);
    }

    pub fn visibleInCamera(self: Prop) bool {
        return self.properties.is(.VisibleInCamera);
    }

    pub fn visibleInReflection(self: Prop) bool {
        return self.properties.is(.VisibleInReflection);
    }

    pub fn visibleInShadow(self: Prop) bool {
        return self.properties.is(.VisibleInShadow);
    }

    pub fn tintedShadow(self: Prop) bool {
        return self.properties.is(.TintedShadow);
    }

    pub fn setVisibleInShadow(self: *Prop, value: bool) void {
        self.properties.set(.VisibleInShadow, value);
    }

    pub fn setVisibility(self: *Prop, in_camera: bool, in_reflection: bool, in_shadow: bool) void {
        self.properties.set(.VisibleInCamera, in_camera);
        self.properties.set(.VisibleInReflection, in_reflection);
        self.properties.set(.VisibleInShadow, in_shadow);
    }

    pub fn configure(self: *Prop, shape: u32, materials: []const u32, scene: Scene) void {
        self.shape = shape;

        self.properties.clear();
        self.properties.set(.VisibleInCamera, true);
        self.properties.set(.VisibleInReflection, true);
        self.properties.set(.VisibleInShadow, true);

        const shape_inst = scene.shape(shape);
        self.properties.set(.TestAABB, shape_inst.isFinite() and shape_inst.isComplex());

        self.properties.set(.Static, true);

        for (materials) |mid| {
            const m = scene.material(mid);

            if (m.masked() or m.tintedShadow()) {
                self.properties.set(.TintedShadow, true);
            }
        }
    }

    pub fn configureAnimated(self: *Prop, local_animation: bool, scene: Scene) void {
        const shape_inst = scene.shape(self.shape);

        self.properties.set(.TestAABB, shape_inst.isFinite());
        self.properties.set(.Static, false);
        self.properties.set(.LocalAnimation, local_animation);
    }

    pub fn setHasParent(self: *Prop) void {
        self.properties.set(.HasParent, true);
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

        if (self.properties.is(.TestAABB) and !scene.propAabbIntersect(entity, ray.*)) {
            return false;
        }

        const static = self.properties.is(.Static);
        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, static);

        return scene.propShape(entity).intersect(ray, trafo, worker, ipo, isec);
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

        if (self.properties.is(.TestAABB) and !scene.propAabbIntersect(entity, ray.*)) {
            return false;
        }

        const static = self.properties.is(.Static);
        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, static);

        return scene.propShape(entity).intersect(ray, trafo, worker, .Normal, isec);
    }

    pub fn intersectP(
        self: Prop,
        entity: usize,
        ray: Ray,
        worker: *Worker,
    ) bool {
        if (!self.visibleInShadow()) {
            return false;
        }

        const scene = worker.scene;

        if (self.properties.is(.TestAABB) and !scene.propAabbIntersect(entity, ray)) {
            return false;
        }

        const static = self.properties.is(.Static);
        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, static);

        return scene.propShape(entity).intersectP(ray, trafo, worker);
    }

    pub fn visibility(self: Prop, entity: usize, ray: Ray, filter: ?Filter, worker: *Worker) ?Vec4f {
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

        if (self.properties.is(.TestAABB) and !scene.propAabbIntersect(entity, ray)) {
            return @splat(4, @as(f32, 1.0));
        }

        const static = self.properties.is(.Static);
        const trafo = scene.propTransformationAtMaybeStatic(entity, ray.time, static);

        return scene.propShape(entity).visibility(ray, trafo, entity, filter, worker);
    }
};
