const Vertex = @import("../vertex.zig").Vertex;
const Probe = Vertex.Probe;
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
        unoccluding: bool = false,
        volume: bool = false,
        caustic: bool = false,
        static: bool = true,
        shadow_catcher: bool = false,
        shadow_catcher_light: bool = false,

        pub inline fn visible(self: Properties, depth: u32) bool {
            if (0 == depth) {
                return self.visible_in_camera;
            }

            return self.visible_in_reflection;
        }
    };

    shape: u32 = Null,

    properties: Properties = .{},

    pub fn visibleInCamera(self: Prop) bool {
        return self.properties.visible_in_camera;
    }

    pub fn visibleInReflection(self: Prop) bool {
        return self.properties.visible_in_reflection;
    }

    pub fn unoccluding(self: Prop) bool {
        return self.properties.unoccluding;
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
        shadow_catcher_light: bool,
    ) void {
        self.properties.visible_in_camera = in_camera;
        self.properties.visible_in_reflection = in_reflection;
        self.properties.shadow_catcher_light = shadow_catcher_light;
    }

    pub fn setShadowCatcher(self: *Prop) void {
        self.properties.shadow_catcher = true;
    }

    pub fn configure(self: *Prop, shape: u32, materials: []const u32, unocc: bool, scene: *const Scene) void {
        self.shape = shape;

        const shape_inst = scene.shape(shape);

        var mono = false;
        var pure_emissive = true;

        if (materials.len > 0) {
            mono = true;

            const mid0 = materials[0];

            for (materials) |mid| {
                const m = scene.material(mid);
                if (m.evaluateVisibility()) {
                    self.properties.evaluate_visibility = true;
                }

                if (m.caustic()) {
                    self.properties.caustic = true;
                }

                if (!m.pureEmissive()) {
                    pure_emissive = false;
                }

                if (mid != mid0) {
                    mono = false;
                }
            }
        }

        self.properties.unoccluding = unocc and shape_inst.finite() and pure_emissive;
        self.properties.volume = shape_inst.finite() and mono and scene.material(materials[0]).ior() < 1.0;
        self.properties.visible_in_shadow = if (self.properties.shadow_catcher) false else self.properties.visible_in_reflection;
    }

    pub fn configureAnimated(self: *Prop, scene: *const Scene) void {
        _ = scene;
        self.properties.static = false;
    }

    pub fn intersect(self: Prop, entity: u32, probe: *const Probe, frag: *Fragment, scene: *const Scene) bool {
        const properties = self.properties;

        if (!properties.visible(probe.depth.surface)) {
            return false;
        }

        if (!scene.propAabbIntersect(entity, probe.ray)) {
            return false;
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, probe.time, properties.static);

        const hit = scene.shape(self.shape).intersect(probe.ray, trafo);
        if (Intersection.Null != hit.primitive) {
            frag.isec = hit;
            frag.trafo = trafo;
            return true;
        }

        return false;
    }

    pub fn fragment(self: Prop, probe: *const Probe, frag: *Fragment, scene: *const Scene) void {
        scene.shape(self.shape).fragment(probe.ray, frag);
    }

    pub fn visibility(self: Prop, entity: u32, probe: *const Probe, sampler: *Sampler, worker: *Worker, tr: *Vec4f) bool {
        const properties = self.properties;
        const scene = worker.scene;

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
        } else if (properties.evaluate_visibility) {
            return shape.visibility(probe.ray, trafo, entity, sampler, scene, tr);
        } else {
            return !shape.intersectP(probe.ray, trafo);
        }
    }

    pub fn emission(
        self: Prop,
        entity: u32,
        vertex: *const Vertex,
        frag: *Fragment,
        split_threshold: f32,
        sampler: *Sampler,
        scene: *const Scene,
    ) Vec4f {
        const properties = self.properties;

        if (!properties.visible(vertex.probe.depth.surface)) {
            return @splat(0.0);
        }

        if (!scene.propAabbIntersect(entity, vertex.probe.ray)) {
            return @splat(0.0);
        }

        const trafo = scene.propTransformationAtMaybeStatic(entity, vertex.probe.time, properties.static);

        frag.trafo = trafo;
        frag.prop = entity;

        return scene.shape(self.shape).emission(vertex, frag, split_threshold, sampler, scene);
    }

    pub fn scatter(
        self: Prop,
        entity: u32,
        probe: *const Probe,
        frag: *Fragment,
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

        const result = scene.shape(self.shape).scatter(probe.ray, probe.depth.volume, trafo, throughput, entity, sampler, worker);
        if (.Absorb == result.event) {
            frag.trafo = trafo;
        }

        return result;
    }
};
