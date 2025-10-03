pub const Context = @import("context.zig").Context;
pub const Transformation = @import("composed_transformation.zig").ComposedTransformation;
const Renderstate = @import("renderstate.zig").Renderstate;
pub const ro = @import("ray_offset.zig");
const Space = @import("space.zig").Space;
pub const Vertex = @import("vertex.zig").Vertex;
pub const Prop = @import("prop/prop.zig").Prop;
const PropBvh = @import("prop/prop_tree.zig").Tree;
const PropBvhBuilder = @import("prop/prop_tree_builder.zig").Builder;
pub const Instancer = @import("prop/instancer.zig").Instancer;
const lgt = @import("light/light.zig");
const Light = lgt.Light;
const LightProperties = lgt.Properties;
const LightTree = @import("light/light_tree.zig").Tree;
const LightTreeBuilder = @import("light/light_tree_builder.zig").Builder;
const int = @import("shape/intersection.zig");
const Fragment = int.Fragment;
const Volume = int.Volume;
pub const Material = @import("material/material.zig").Material;
pub const shp = @import("shape/shape.zig");
pub const Shape = shp.Shape;
const ShapeSampler = @import("shape/shape_sampler.zig").Sampler;
const ShapeSamplerCache = @import("shape/shape_sampler_cache.zig").Cache;
const Probe = @import("shape/probe.zig").Probe;
const Image = @import("../image/image.zig").Image;
const Procedural = @import("../texture/procedural.zig").Procedural;
const Sampler = @import("../sampler/sampler.zig").Sampler;
const Sky = @import("../sky/sky.zig").Sky;
const Filesystem = @import("../file/system.zig").System;
const hlp = @import("../rendering/integrator/helper.zig");
const ggx = @import("material/ggx.zig");

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Mat4x4 = math.Mat4x4;
const Distribution1D = math.Distribution1D;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayList;

pub const Scene = struct {
    pub const Lights = LightTree.Lights;
    pub const LightPick = Distribution1D.Discrete;
    pub const SamplesTo = Shape.SamplesTo;
    pub const UnitsPerSecond = Space.UnitsPerSecond;
    pub const TickDuration = Space.TickDuration;
    const NumSteps = 4;
    const Interval = 1.0 / @as(f32, @floatFromInt(NumSteps));

    pub fn absoluteTime(dtime: f64) u64 {
        return @intFromFloat(@round(@as(f64, @floatFromInt(UnitsPerSecond)) * dtime));
    }

    pub fn secondsSince(time: u64, time_start: u64) f32 {
        return @floatCast(@as(f64, @floatFromInt(time - time_start)) / @as(f64, @floatFromInt(UnitsPerSecond)));
    }

    pub const NumReservedProps = 32;

    pub const Null = Prop.Null;

    pub const ShapeID = enum(u32) {
        Canopy,
        Cube,
        Disk,
        Distant,
        Dome,
        Rectangle,
        Sphere,
    };

    images: List(Image) = .empty,
    materials: List(Material) = .empty,
    shapes: List(Shape),
    instancers: List(Instancer),
    samplers: ShapeSamplerCache = .{},

    specular_threshold: f32 = ggx.MinAlpha,
    num_interpolation_frames: u32 = 0,

    frame_start: u64 = undefined,

    bvh_builder: PropBvhBuilder,
    light_tree_builder: LightTreeBuilder = .{},

    solid_bvh: PropBvh = .{},
    unoccluding_bvh: PropBvh = .{},
    volume_bvh: PropBvh = .{},

    caustic_aabb: AABB = undefined,

    props: List(Prop),
    prop_parts: List(u32),
    prop_space: Space,

    lights: List(Light),
    light_aabbs: List(AABB),
    light_cones: List(Vec4f),

    material_ids: List(u32),
    light_ids: List(u32),

    light_temp_powers: []f32,
    light_distribution: Distribution1D = .{},
    light_tree: LightTree = .{},

    finite_props: List(u32),
    infinite_props: List(u32),
    unoccluding_props: List(u32),
    volume_props: List(u32),

    sky: Sky = .{},

    procedural: Procedural = .{},

    pub fn init(alloc: Allocator) !Scene {
        var shapes = try List(Shape).initCapacity(alloc, 16);
        try shapes.append(alloc, .{ .Canopy = .{} });
        try shapes.append(alloc, .{ .Cube = .{} });
        try shapes.append(alloc, .{ .Disk = .{} });
        try shapes.append(alloc, .{ .Distant = .{} });
        try shapes.append(alloc, .{ .Dome = .{} });
        try shapes.append(alloc, .{ .Rectangle = .{} });
        try shapes.append(alloc, .{ .Sphere = .{} });

        return Scene{
            .shapes = shapes,
            .instancers = try List(Instancer).initCapacity(alloc, 4),
            .bvh_builder = try PropBvhBuilder.init(alloc),
            .props = try List(Prop).initCapacity(alloc, NumReservedProps),
            .prop_space = try Space.init(alloc, NumReservedProps),
            .prop_parts = try List(u32).initCapacity(alloc, NumReservedProps),
            .lights = try List(Light).initCapacity(alloc, NumReservedProps),
            .light_aabbs = try List(AABB).initCapacity(alloc, NumReservedProps),
            .light_cones = try List(Vec4f).initCapacity(alloc, NumReservedProps),
            .material_ids = try List(u32).initCapacity(alloc, NumReservedProps),
            .light_ids = try List(u32).initCapacity(alloc, NumReservedProps),
            .light_temp_powers = try alloc.alloc(f32, NumReservedProps),
            .finite_props = try List(u32).initCapacity(alloc, NumReservedProps),
            .infinite_props = try List(u32).initCapacity(alloc, 2),
            .unoccluding_props = try List(u32).initCapacity(alloc, NumReservedProps),
            .volume_props = try List(u32).initCapacity(alloc, NumReservedProps),
        };
    }

    fn deinitResources(comptime T: type, alloc: Allocator, resources: *List(T)) void {
        for (resources.items) |*r| {
            r.deinit(alloc);
        }

        resources.deinit(alloc);
    }

    pub fn deinit(self: *Scene, alloc: Allocator) void {
        self.light_tree_builder.deinit(alloc);
        self.solid_bvh.deinit(alloc);
        self.unoccluding_bvh.deinit(alloc);
        self.volume_bvh.deinit(alloc);
        self.bvh_builder.deinit(alloc);

        self.volume_props.deinit(alloc);
        self.unoccluding_props.deinit(alloc);
        self.infinite_props.deinit(alloc);
        self.finite_props.deinit(alloc);

        self.light_tree.deinit(alloc);
        self.light_distribution.deinit(alloc);
        alloc.free(self.light_temp_powers);

        self.light_ids.deinit(alloc);
        self.material_ids.deinit(alloc);
        self.light_cones.deinit(alloc);
        self.light_aabbs.deinit(alloc);
        self.lights.deinit(alloc);
        self.samplers.deinit(alloc);
        self.prop_parts.deinit(alloc);
        self.prop_space.deinit(alloc);
        self.props.deinit(alloc);

        self.procedural.deinit(alloc);

        deinitResources(Instancer, alloc, &self.instancers);
        deinitResources(Shape, alloc, &self.shapes);
        deinitResources(Material, alloc, &self.materials);
        deinitResources(Image, alloc, &self.images);
    }

    pub fn clear(self: *Scene) void {
        self.num_interpolation_frames = 0;

        self.volume_props.clearRetainingCapacity();
        self.unoccluding_props.clearRetainingCapacity();
        self.infinite_props.clearRetainingCapacity();
        self.finite_props.clearRetainingCapacity();
        self.light_ids.clearRetainingCapacity();
        self.material_ids.clearRetainingCapacity();
        self.light_cones.clearRetainingCapacity();
        self.light_aabbs.clearRetainingCapacity();
        self.lights.clearRetainingCapacity();
        self.prop_parts.clearRetainingCapacity();
        self.prop_space.clear();
        self.props.clearRetainingCapacity();
    }

    pub fn aabb(self: *const Scene) AABB {
        return self.solid_bvh.aabb();
    }

    pub fn causticAabb(self: *const Scene) AABB {
        return self.caustic_aabb;
    }

    pub fn finite(self: *const Scene) bool {
        return 0 == self.infinite_props.items.len;
    }

    pub fn compile(
        self: *Scene,
        alloc: Allocator,
        camera_pos: Vec4f,
        time: u64,
        threads: *Threads,
        fs: *Filesystem,
    ) !void {
        const frames_start = time - (time % TickDuration);
        self.frame_start = frames_start;

        try self.sky.compile(alloc, time, self, threads, fs);

        self.calculateWorldBounds(camera_pos);

        try self.bvh_builder.build(alloc, &self.solid_bvh, self.finite_props.items, self.prop_space.aabbs.items, threads);

        try self.bvh_builder.build(alloc, &self.unoccluding_bvh, self.unoccluding_props.items, self.prop_space.aabbs.items, threads);

        try self.bvh_builder.build(alloc, &self.volume_bvh, self.volume_props.items, self.prop_space.aabbs.items, threads);

        const num_lights = self.lights.items.len;
        if (num_lights > self.light_temp_powers.len) {
            self.light_temp_powers = try alloc.realloc(self.light_temp_powers, num_lights);
        }

        for (0..num_lights) |i| {
            try self.propPrepareSampling(alloc, i, time, threads);
            self.light_temp_powers[i] = self.lightPower(i);
        }

        try self.light_distribution.configure(alloc, self.light_temp_powers[0..num_lights], 0);

        try self.light_tree_builder.build(alloc, &self.light_tree, self, threads);

        var caustic_aabb: AABB = .empty;
        for (self.finite_props.items) |i| {
            if (self.props.items[i].caustic()) {
                caustic_aabb.mergeAssign(self.prop_space.aabbs.items[i]);
            }
        }

        self.caustic_aabb = caustic_aabb;
    }

    pub fn intersect(self: *const Scene, probe: *Probe, sampler: *Sampler, frag: *Fragment) bool {
        return self.solid_bvh.intersect(probe, sampler, self, frag);
    }

    pub fn visibility(self: *const Scene, probe: Probe, sampler: *Sampler, context: Context, tr: *Vec4f) bool {
        if (self.solid_bvh.visibility(false, probe, sampler, context, tr)) {
            return self.volume_bvh.visibility(true, probe, sampler, context, tr);
        }

        return false;
    }

    pub fn scatter(
        self: *const Scene,
        probe: *Probe,
        frag: *Fragment,
        throughput: *Vec4f,
        sampler: *Sampler,
        context: Context,
    ) void {
        if (0 == self.volume_bvh.num_nodes) {
            frag.event = .Pass;
            frag.vol_li = @splat(0.0);
            return;
        }

        self.volume_bvh.scatter(probe, frag, throughput, sampler, context);
    }

    pub fn commitMaterials(self: *const Scene, alloc: Allocator, threads: *Threads) !void {
        for (self.materials.items) |*m| {
            try m.commit(alloc, self, threads);
        }
    }

    pub fn calculateNumInterpolationFrames(self: *Scene, frame_step: u64, frame_duration: u64) void {
        const num_frames = countFrames(frame_step, frame_duration) + 1;
        self.num_interpolation_frames = @max(self.num_interpolation_frames, num_frames);
    }

    pub fn createEntity(self: *Scene, alloc: Allocator) !u32 {
        const p = try self.allocateProp(alloc);

        self.props.items[p].configureShape(@intFromEnum(ShapeID.Distant), &.{}, false, self);

        return p;
    }

    pub fn createPropShape(self: *Scene, alloc: Allocator, shape_id: u32, materials: []const u32, unoccluding: bool, is_prototype: bool) !u32 {
        const p = try self.allocateProp(alloc);

        self.props.items[p].configureShape(shape_id, materials, unoccluding, self);

        const shape_inst = self.shape(shape_id);
        const num_parts = shape_inst.numParts();

        const parts_start: u32 = @intCast(self.material_ids.items.len);
        self.prop_parts.items[p] = parts_start;

        var i: u32 = 0;
        while (i < num_parts) : (i += 1) {
            const material_id = if (materials.len > 0) materials[shape_inst.partIdToMaterialId(i)] else 0;
            try self.material_ids.append(alloc, material_id);
            try self.light_ids.append(alloc, Null);
        }

        if (!is_prototype) {
            try self.classifyProp(alloc, p);
        }

        return p;
    }

    pub fn createPropInstancer(self: *Scene, alloc: Allocator, shape_id: u32, is_prototype: bool) !u32 {
        const p = try self.allocateProp(alloc);

        const instancer_inst = self.instancer(shape_id);

        self.props.items[p].configureIntancer(shape_id, instancer_inst.solid(), instancer_inst.volume());

        if (!is_prototype) {
            try self.classifyProp(alloc, p);
        }

        return p;
    }

    pub fn createPropInstance(self: *Scene, alloc: Allocator, entity: u32) !u32 {
        const p = try self.allocateProp(alloc);

        self.props.items[p] = self.props.items[entity];
        self.prop_parts.items[p] = self.prop_parts.items[entity];

        try self.classifyProp(alloc, p);

        return p;
    }

    pub fn propAllocateFrames(self: *Scene, alloc: Allocator, entity: u32) !void {
        const num_frames = self.num_interpolation_frames;
        try self.prop_space.allocateFrames(alloc, entity, num_frames);

        self.props.items[entity].configureAnimated(self);
    }

    fn classifyProp(self: *Scene, alloc: Allocator, p: u32) !void {
        const po = self.prop(p);

        if (po.volume()) {
            try self.volume_props.append(alloc, p);
        }

        if (po.solid()) {
            if (po.finite(self)) {
                if (po.unoccluding()) {
                    try self.unoccluding_props.append(alloc, p);
                } else {
                    try self.finite_props.append(alloc, p);
                }
            } else {
                try self.infinite_props.append(alloc, p);
            }
        }
    }

    pub fn createLight(self: *Scene, alloc: Allocator, entity: u32) !void {
        const shape_inst = self.propShape(entity);
        const num_parts = shape_inst.numParts();
        const shadow_catcher_light = self.propIsShadowCatcherLight(entity);

        var i: u32 = 0;
        while (i < num_parts) : (i += 1) {
            const mat = self.propMaterial(entity, i);
            if (!mat.emissive()) {
                continue;
            }

            if (mat.scatteringVolume()) {
                if (shape_inst.analytical() and mat.emissionImageMapped()) {
                    try self.allocateLight(alloc, .VolumeImage, false, shadow_catcher_light, entity, i);
                } else {
                    try self.allocateLight(alloc, .Volume, false, shadow_catcher_light, entity, i);
                }
            } else {
                const two_sided = mat.twoSided();

                if (shape_inst.analytical() and mat.emissionImageMapped()) {
                    try self.allocateLight(alloc, .PropImage, two_sided, shadow_catcher_light, entity, i);
                } else {
                    try self.allocateLight(alloc, .Prop, two_sided, shadow_catcher_light, entity, i);
                }
            }
        }
    }

    pub fn propWorldPosition(self: *const Scene, entity: u32) Vec4f {
        const f = self.prop_space.frames.items[entity];
        if (Null == f) {
            return self.prop_space.world_transformations.items[entity].position;
        }

        return self.prop_space.keyframes.items[f].position;
    }

    pub fn propTransformationAt(self: *const Scene, entity: u32, time: u64) Transformation {
        const f = self.prop_space.frames.items[entity];
        return self.prop_space.transformationAtMaybeStatic(entity, time, self.frame_start, Null == f);
    }

    pub fn propSetVisibility(
        self: *Scene,
        entity: u32,
        in_camera: bool,
        in_reflection: bool,
        shadow_catcher_light: bool,
    ) void {
        self.props.items[entity].setVisibility(in_camera, in_reflection, shadow_catcher_light);
    }

    pub fn propSetShadowCatcher(self: *Scene, entity: u32) void {
        self.props.items[entity].setShadowCatcher();
    }

    fn propPrepareSampling(self: *Scene, alloc: Allocator, light_id: usize, time: u64, threads: *Threads) !void {
        var l = &self.lights.items[light_id];

        const entity = l.prop;
        const part = l.part;

        const shape_inst = self.propShape(entity);

        const p = self.prop_parts.items[entity] + part;

        self.light_ids.items[p] = @intCast(light_id);

        const shape_id = self.propShapeId(entity);
        const material_id = self.material_ids.items[p];

        const trafo = self.prop_space.transformationAt(entity, time, self.frame_start);
        const extent = if (l.volumetric()) shape_inst.volume(trafo.scale()) else shape_inst.area(part, trafo.scale());

        const sampler_id = try self.samplers.prepareSampling(
            alloc,
            shape_inst,
            shape_id,
            part,
            material_id,
            self,
            threads,
        );

        l.sampler = sampler_id;

        const sampler = self.samplers.sampler(sampler_id);
        const average_radiance = sampler.averageEmission(self.material(material_id));

        const f = self.prop_space.frames.items[entity];
        const part_aabb = sampler.impl.aabb(shape_inst);
        const part_cone = sampler.impl.cone(shape_inst);

        if (Null == f) {
            var bb = part_aabb.transform(trafo.objectToWorld());
            bb.cacheRadius();

            self.light_aabbs.items[light_id] = bb;

            const tc = trafo.objectToWorldNormal(part_cone);
            self.light_cones.items[light_id] = Vec4f{ tc[0], tc[1], tc[2], part_cone[3] };
        } else {
            const frames = self.prop_space.keyframes.items.ptr + f;

            var rotation = math.quaternion.toMat3x3(frames[0].rotation);
            var composed = Mat4x4.compose(rotation, frames[0].scale, frames[0].position);

            var bb = part_aabb.transform(composed);

            const tc = rotation.transformVector(part_cone);
            var cone = Vec4f{ tc[0], tc[1], tc[2], part_cone[3] };

            const len = self.num_interpolation_frames - 1;
            var i: u32 = 0;
            while (i < len) : (i += 1) {
                const a = frames[i];
                const b = frames[i + 1];

                var t = Interval;
                var j: u32 = NumSteps - 1;
                while (j > 0) : (j -= 1) {
                    const inter = a.lerp(b, t);

                    rotation = math.quaternion.toMat3x3(inter.rotation);
                    composed = Mat4x4.compose(rotation, inter.scale, inter.position);

                    bb.mergeAssign(part_aabb.transform(composed));
                    cone = math.cone.merge(cone, math.cone.transform(rotation, cone));

                    t += Interval;
                }
            }

            rotation = math.quaternion.toMat3x3(frames[len].rotation);
            composed = Mat4x4.compose(rotation, frames[len].scale, frames[len].position);

            bb.mergeAssign(part_aabb.transform(composed));
            cone = math.cone.merge(cone, math.cone.transform(rotation, cone));

            bb.cacheRadius();

            self.light_aabbs.items[light_id] = bb;
            self.light_cones.items[light_id] = cone;
        }

        const mat = self.material(material_id);

        const total_emission = mat.totalEmission(average_radiance, extent);

        self.light_aabbs.items[light_id].bounds[0][3] = math.hmax3(
            self.lights.items[light_id].power(total_emission, self.aabb(), self),
        );
    }

    pub fn propAabbIntersect(self: *const Scene, entity: u32, ray: math.Ray) bool {
        return self.prop_space.aabbs.items[entity].intersect(ray);
    }

    pub fn propAabbIntersectP(self: *const Scene, entity: u32, ray: math.Ray) ?f32 {
        return self.prop_space.aabbs.items[entity].intersectP(ray);
    }

    pub fn propRadius(self: *const Scene, entity: u32) f32 {
        return self.prop_space.aabbs.items[entity].cachedRadius();
    }

    pub fn propShapeId(self: *const Scene, entity: usize) u32 {
        return self.props.items[entity].resource;
    }

    pub fn propShape(self: *const Scene, entity: usize) *Shape {
        return &self.shapes.items[self.props.items[entity].resource];
    }

    pub fn propIsShadowCatcher(self: *const Scene, entity: u32) bool {
        return self.props.items[entity].properties.shadow_catcher;
    }

    pub fn propIsShadowCatcherLight(self: *const Scene, entity: u32) bool {
        return self.props.items[entity].properties.shadow_catcher_light;
    }

    pub fn propMaterialId(self: *const Scene, entity: u32, part: u32) u32 {
        const p = self.prop_parts.items[entity] + part;
        return self.material_ids.items[p];
    }

    pub fn propMaterial(self: *const Scene, entity: u32, part: u32) *Material {
        const p = self.prop_parts.items[entity] + part;
        return &self.materials.items[self.material_ids.items[p]];
    }

    pub fn propOpacity(self: *const Scene, entity: u32, part: u32, uv: Vec2f, sampler: *Sampler) bool {
        return self.propMaterial(entity, part).super().stochasticOpacity(uv, sampler, self);
    }

    pub fn propLightId(self: *const Scene, entity: u32, part: u32) u32 {
        const p = self.prop_parts.items[entity] + part;
        return self.light_ids.items[p];
    }

    pub fn image(self: *const Scene, image_id: u32) Image {
        return self.images.items[image_id];
    }

    pub fn imagePtr(self: *const Scene, image_id: u32) *Image {
        return &self.images.items[image_id];
    }

    pub fn material(self: *const Scene, material_id: u32) *Material {
        return &self.materials.items[material_id];
    }

    pub fn shape(self: *const Scene, shape_id: u32) *const Shape {
        return &self.shapes.items[shape_id];
    }

    pub fn instancer(self: *const Scene, shape_id: u32) *const Instancer {
        return &self.instancers.items[shape_id];
    }

    pub fn prop(self: *const Scene, index: u32) Prop {
        return self.props.items[index];
    }

    pub fn numLights(self: *const Scene) u32 {
        return @intCast(self.lights.items.len);
    }

    pub fn light(self: *const Scene, id: u32) Light {
        return self.lights.items[id];
    }

    pub fn shapeSampler(self: *const Scene, id: u32) *const ShapeSampler {
        return &self.samplers.resources.items[id];
    }

    pub fn randomLight(self: *const Scene, random: f32) LightPick {
        return self.light_distribution.sampleDiscrete(random);
    }

    pub fn randomLightSpatial(
        self: *const Scene,
        p: Vec4f,
        n: Vec4f,
        total_sphere: bool,
        random: f32,
        split_threshold: f32,
        buffer: *Lights,
    ) []LightPick {
        // _ = p;
        // _ = n;
        // _ = total_sphere;
        // _ = split;

        // buffer[0] = self.light_distribution.sampleDiscrete(random);
        // return buffer[0..1];

        return self.light_tree.randomLight(p, n, total_sphere, random, split_threshold, self, buffer);
    }

    pub fn lightPdfSpatial(self: *const Scene, id: u32, vertex: *const Vertex, split_threshold: f32) f32 {
        // _ = p;
        // _ = n;
        // _ = total_sphere;
        // _ = split;

        // const pdf = self.light_distribution.pdfI(id);
        // return .{ .offset = id, .pdf = pdf };

        return self.light_tree.pdf(vertex.origin, vertex.geo_n, vertex.state.translucent, split_threshold, id, self);
    }

    pub fn lightPdf(self: *const Scene, vertex: *const Vertex, frag: *const Fragment, split_threshold: f32) f32 {
        const light_id = frag.lightId(self);

        if (vertex.state.singular or !Light.isLight(light_id)) {
            return 1.0;
        }

        const select_pdf = self.lightPdfSpatial(light_id, vertex, split_threshold);
        const sample_pdf = self.light(light_id).pdf(vertex, frag, split_threshold, self);
        return hlp.powerHeuristic(vertex.bxdf_pdf, sample_pdf * select_pdf);
    }

    pub fn lightTwoSided(self: *const Scene, light_id: u32) bool {
        return self.lights.items[light_id].two_sided;
    }

    pub fn lightPower(self: *const Scene, light_id: usize) f32 {
        return self.light_aabbs.items[light_id].bounds[0][3];
    }

    pub fn lightAabb(self: *const Scene, light_id: u32) AABB {
        return self.light_aabbs.items[light_id];
    }

    pub fn lightCone(self: *const Scene, light_id: u32) Vec4f {
        return self.light_cones.items[light_id];
    }

    pub fn lightProperties(self: *const Scene, light_id: u32) LightProperties {
        const box = self.light_aabbs.items[light_id];
        const pos = box.position();

        return .{
            .sphere = .{ pos[0], pos[1], pos[2], box.cachedRadius() },
            .cone = self.light_cones.items[light_id],
            .power = self.light_aabbs.items[light_id].bounds[0][3],
            .two_sided = self.lights.items[light_id].two_sided,
        };
    }

    fn allocateProp(self: *Scene, alloc: Allocator) !u32 {
        try self.props.append(alloc, .{});
        try self.prop_space.allocateInstance(alloc);
        try self.prop_parts.append(alloc, 0);

        return @intCast(self.props.items.len - 1);
    }

    fn allocateLight(
        self: *Scene,
        alloc: Allocator,
        class: Light.Class,
        two_sided: bool,
        shadow_catcher_light: bool,
        entity: u32,
        part: u32,
    ) !void {
        try self.lights.append(alloc, .{
            .class = class,
            .two_sided = two_sided,
            .shadow_catcher_light = shadow_catcher_light,
            .prop = entity,
            .part = part,
            .sampler = undefined,
        });
        try self.light_aabbs.append(alloc, AABB.init(@splat(0.0), @splat(0.0)));
        try self.light_cones.append(alloc, .{ 0.0, 0.0, 0.0, -1.0 });
    }

    pub fn createSky(self: *Scene, alloc: Allocator) !*Sky {
        try self.sky.configure(alloc, self);
        return &self.sky;
    }

    pub fn createImage(self: *Scene, alloc: Allocator, item: Image) !u32 {
        try self.images.append(alloc, item);
        return @intCast(self.images.items.len - 1);
    }

    pub fn createMaterial(self: *Scene, alloc: Allocator, item: Material) !u32 {
        try self.materials.append(alloc, item);
        return @intCast(self.materials.items.len - 1);
    }

    fn calculateWorldBounds(self: *Scene, camera_pos: Vec4f) void {
        for (0..self.prop_space.frames.items.len) |entity| {
            const p: u32 = @truncate(entity);
            const prop_aabb = self.prop(p).localAabb(self);

            self.prop_space.calculateWorldBounds(p, prop_aabb, camera_pos, self.num_interpolation_frames);
        }
    }

    fn countFrames(frame_step: u64, frame_duration: u64) u32 {
        const a: u32 = @max(@as(u32, @intCast(frame_duration / TickDuration)), 1);
        const b: u32 = if (matching(frame_step, TickDuration)) 0 else 1;
        const c: u32 = if (matching(frame_duration, TickDuration)) 0 else 1;

        return a + b + c;
    }

    fn matching(a: u64, b: u64) bool {
        return 0 == (if (a > b) a % b else (if (0 == a) 0 else b % a));
    }
};
