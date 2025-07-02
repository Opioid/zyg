const Context = @import("../context.zig").Context;
const Scene = @import("../scene.zig").Scene;
const Space = @import("../space.zig").Space;
const Vertex = @import("../vertex.zig").Vertex;
const Material = @import("../material/material.zig").Material;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const int = @import("../shape/intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Probe = @import("../shape/probe.zig").Probe;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;

const math = @import("base").math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Prop = struct {
    pub const Null: u32 = 0xFFFFFFFF;

    const Properties = packed struct {
        visible_in_camera: bool = true,
        visible_in_reflection: bool = true,
        visible_in_shadow: bool = true,
        evaluate_visibility: bool = false,
        unoccluding: bool = false,
        solid: bool = true,
        volume: bool = false,
        caustic: bool = false,
        static: bool = true,
        instancer: bool = false,
        shadow_catcher: bool = false,
        shadow_catcher_light: bool = false,

        pub inline fn visible(self: Properties, depth: u32) bool {
            if (0 == depth) {
                return self.visible_in_camera;
            }

            return self.visible_in_reflection;
        }
    };

    resource: u32 = Null,

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

    pub fn solid(self: Prop) bool {
        return self.properties.solid;
    }

    pub fn volume(self: Prop) bool {
        return self.properties.volume;
    }

    pub fn caustic(self: Prop) bool {
        return self.properties.caustic;
    }

    pub fn instancer(self: Prop) bool {
        return self.properties.instancer;
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
        self.properties.visible_in_shadow = if (self.properties.shadow_catcher) false else in_reflection;
    }

    pub fn setShadowCatcher(self: *Prop) void {
        self.properties.shadow_catcher = true;
        self.properties.visible_in_shadow = false;
    }

    pub fn configureShape(self: *Prop, resource: u32, materials: []const u32, unocc: bool, scene: *const Scene) void {
        self.resource = resource;

        const shape_inst = scene.shape(resource);

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

        const volumetric = shape_inst.finite() and mono and scene.material(materials[0]).ior() < 1.0;

        self.properties.solid = !volumetric;
        self.properties.volume = volumetric;

        self.properties.unoccluding = unocc and shape_inst.finite() and pure_emissive;
    }

    pub fn configureIntancer(self: *Prop, resource: u32, solidb: bool, volumetric: bool) void {
        self.properties.solid = solidb;
        self.properties.volume = volumetric;
        self.resource = resource;
        self.properties.instancer = true;
    }

    pub fn configureAnimated(self: *Prop, scene: *const Scene) void {
        _ = scene;
        self.properties.static = false;
    }

    pub fn localAabb(self: Prop, scene: *const Scene) AABB {
        if (self.properties.instancer) {
            return scene.instancer(self.resource).aabb();
        } else {
            return scene.shape(self.resource).aabb(scene.frame_duration);
        }
    }

    pub fn finite(self: Prop, scene: *const Scene) bool {
        if (self.properties.instancer) {
            return true;
        } else {
            return scene.shape(self.resource).finite();
        }
    }

    pub fn intersect(
        self: Prop,
        entity: u32,
        prototype: u32,
        probe: Probe,
        sampler: *Sampler,
        scene: *const Scene,
        space: *const Space,
        isec: *Intersection,
    ) bool {
        const properties = self.properties;

        if (!properties.visible(probe.depth.surface)) {
            return false;
        }

        if (!space.intersectAABB(entity, probe.ray)) {
            return false;
        }

        const trafo = space.transformationAtMaybeStatic(entity, probe.time, scene.current_time_start, properties.static);

        if (properties.instancer) {
            return scene.instancer(self.resource).intersect(probe, trafo, sampler, scene, isec);
        } else {
            const shape = scene.shape(self.resource);

            if (properties.evaluate_visibility) {
                return shape.intersectOpacity(probe, trafo, prototype, sampler, scene, isec);
            } else {
                return shape.intersect(probe, trafo, scene.current_time_start, isec);
            }
        }
    }

    pub fn visibility(
        self: Prop,
        comptime Volumetric: bool,
        entity: u32,
        prototype: u32,
        probe: Probe,
        sampler: *Sampler,
        context: Context,
        space: *const Space,
        tr: *Vec4f,
    ) bool {
        const properties = self.properties;

        if (!properties.visible_in_shadow) {
            return true;
        }

        if (!space.intersectAABB(entity, probe.ray)) {
            return true;
        }

        const scene = context.scene;

        const trafo = space.transformationAtMaybeStatic(entity, probe.time, scene.current_time_start, properties.static);

        if (properties.instancer) {
            return scene.instancer(self.resource).visibility(Volumetric, probe, trafo, sampler, context, tr);
        } else {
            const shape = scene.shape(self.resource);

            if (Volumetric) {
                return shape.transmittance(probe, trafo, prototype, sampler, context, tr);
            } else if (properties.evaluate_visibility) {
                return shape.visibility(probe, trafo, prototype, sampler, context, tr);
            } else {
                return !shape.intersectP(probe, trafo, scene.current_time_start);
            }
        }
    }

    pub fn emission(
        self: Prop,
        entity: u32,
        vertex: *const Vertex,
        frag: *Fragment,
        split_threshold: f32,
        sampler: *Sampler,
        context: Context,
    ) Vec4f {
        const properties = self.properties;
        const scene = context.scene;

        if (!properties.visible(vertex.probe.depth.surface)) {
            return @splat(0.0);
        }

        if (!scene.propAabbIntersect(entity, vertex.probe.ray)) {
            return @splat(0.0);
        }

        const trafo = scene.prop_space.transformationAtMaybeStatic(entity, vertex.probe.time, scene.current_time_start, properties.static);

        frag.isec.trafo = trafo;
        frag.prop = entity;

        return scene.shape(self.resource).emission(vertex, frag, split_threshold, sampler, context);
    }

    pub fn scatter(
        self: Prop,
        entity: u32,
        prototype: u32,
        probe: Probe,
        isec: *Intersection,
        throughput: Vec4f,
        sampler: *Sampler,
        context: Context,
        space: *const Space,
    ) int.Volume {
        const properties = self.properties;
        const scene = context.scene;

        if (!space.intersectAABB(entity, probe.ray)) {
            return int.Volume.initPass(@splat(1.0));
        }

        const trafo = space.transformationAtMaybeStatic(entity, probe.time, scene.current_time_start, properties.static);

        if (properties.instancer) {
            return scene.instancer(self.resource).scatter(probe, trafo, isec, throughput, sampler, context);
        } else {
            const result = scene.shape(self.resource).scatter(probe, trafo, throughput, prototype, sampler, context);

            isec.prototype = Intersection.Null;

            if (.Absorb == result.event) {
                isec.trafo = trafo;
            }

            return result;
        }
    }
};
