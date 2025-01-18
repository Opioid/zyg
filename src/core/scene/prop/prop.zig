const Probe = @import("../vertex.zig").Vertex.Probe;
const Material = @import("../material/material.zig").Material;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Scene = @import("../scene.zig").Scene;
const int = @import("../shape/intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
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
        static: bool = true,
        shadow_catcher: bool = false,
        shadow_catcher_light: bool = false,
    };

    shape: u32 = Null,

    properties: Properties = .{},

    fn visible(self: Prop, depth: u32) bool {
        const properties = self.properties;

        if (properties.volume) {
            return false;
        }

        if (0 == depth) {
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

    pub fn volume(self: Prop) bool {
        return self.properties.volume;
    }

    pub fn caustic(self: Prop) bool {
        return self.properties.caustic;
    }

    pub fn setVisibility(
        self: *Prop,
        in_camera: bool,
        in_reflection: bool,
        in_shadow: bool,
        shadow_catcher_light: bool,
    ) void {
        self.properties.visible_in_camera = in_camera;
        self.properties.visible_in_reflection = in_reflection;
        self.properties.visible_in_shadow = in_shadow;
        self.properties.shadow_catcher_light = shadow_catcher_light;
    }

    pub fn setShadowCatcher(self: *Prop) void {
        self.properties.shadow_catcher = true;
        self.properties.visible_in_camera = true;
        self.properties.visible_in_reflection = false;
        self.properties.visible_in_shadow = false;
    }

    pub fn configure(self: *Prop, shape: u32, materials: []const u32, scene: *const Scene) void {
        self.shape = shape;

        const shape_inst = scene.shape(shape);

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

        self.properties.volume = shape_inst.finite() and mono and scene.material(materials[0]).ior() < 1.0;
    }

    pub fn configureAnimated(self: *Prop, scene: *const Scene) void {
        _ = scene;
        self.properties.static = false;
    }

    pub fn intersect(self: Prop, entity: u32, probe: *Probe, frag: *Fragment, override_visibility: bool, scene: *const Scene) bool {
        if (!override_visibility and !self.visible(probe.depth.surface)) {
            return false;
        }

        const properties = self.properties;

        if (!scene.propAabbIntersect(entity, probe.ray)) {
            return false;
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, probe.time, properties.static);

        const hit = scene.shape(self.shape).intersect(probe.ray, trafo);
        if (Intersection.Null != hit.primitive) {
            probe.ray.max_t = hit.t;
            frag.isec = hit;
            frag.trafo = trafo;
            return true;
        }

        return false;
    }

    pub fn fragment(self: Prop, probe: *const Probe, frag: *Fragment, scene: *const Scene) void {
        scene.shape(self.shape).fragment(probe.ray, frag);
    }

    pub fn intersectP(self: Prop, entity: u32, probe: *const Probe, scene: *const Scene) bool {
        const properties = self.properties;

        if (!properties.visible_in_shadow) {
            return false;
        }

        if (!scene.propAabbIntersect(entity, probe.ray)) {
            return false;
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, probe.time, properties.static);

        return scene.shape(self.shape).intersectP(probe.ray, trafo);
    }

    pub fn visibility(self: Prop, entity: u32, probe: *const Probe, sampler: *Sampler, worker: *Worker, tr: *Vec4f) bool {
        const properties = self.properties;
        const scene = worker.scene;

        if (!properties.evaluate_visibility) {
            if (self.intersectP(entity, probe, scene)) {
                return false;
            }

            return true;
        }

        if (!properties.visible_in_shadow) {
            return true;
        }

        if (!scene.propAabbIntersect(entity, probe.ray)) {
            return true;
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, probe.time, properties.static);

        const shape = scene.shape(self.shape);

        if (properties.volume) {
            return shape.transmittance(probe.ray, probe.depth.volume, trafo, entity, sampler, worker, tr);
        } else {
            return shape.visibility(probe.ray, trafo, entity, sampler, scene, tr);
        }
    }

    pub fn scatter(
        self: Prop,
        entity: u32,
        probe: *const Probe,
        throughput: Vec4f,
        sampler: *Sampler,
        worker: *Worker,
    ) int.Volume {
        const properties = self.properties;
        const scene = worker.scene;

        if (!scene.propAabbIntersect(entity, probe.ray)) {
            return int.Volume.initPass(@splat(1.0));
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, probe.time, properties.static);

        return scene.shape(self.shape).scatter(probe.ray, probe.depth.volume, trafo, throughput, entity, sampler, worker);
    }
};
