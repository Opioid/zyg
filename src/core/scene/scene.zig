pub const Prop = @import("prop/prop.zig").Prop;
const PropBvh = @import("prop/prop_tree.zig").Tree;
const PropBvhBuilder = @import("prop/prop_tree_builder.zig").Builder;
const lgt = @import("light/light.zig");
const Light = lgt.Light;
const LightProperties = lgt.Properties;
const LightTree = @import("light/light_tree.zig").Tree;
const LightTreeBuilder = @import("light/light_tree_builder.zig").Builder;
const int = @import("shape/intersection.zig");
const Fragment = int.Fragment;
const Volume = int.Volume;
pub const Material = @import("material/material.zig").Material;
const shp = @import("shape/shape.zig");
pub const Shape = shp.Shape;
const Probe = @import("vertex.zig").Vertex.Probe;
const Image = @import("../image/image.zig").Image;
const Sampler = @import("../sampler/sampler.zig").Sampler;
pub const Transformation = @import("composed_transformation.zig").ComposedTransformation;
const Sky = @import("../sky/sky.zig").Sky;
const Filesystem = @import("../file/system.zig").System;
const Worker = @import("../rendering/worker.zig").Worker;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;
const Mat4x4 = math.Mat4x4;
const Distribution1D = math.Distribution1D;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub const Scene = struct {
    pub const Lights = LightTree.Lights;
    pub const LightPick = Distribution1D.Discrete;
    pub const Units_per_second: u64 = 705600000;
    pub const Tick_duration = Units_per_second / 60;
    const Num_steps = 4;
    const Interval = 1.0 / @as(f32, @floatFromInt(Num_steps));

    pub fn absoluteTime(dtime: f64) u64 {
        return @as(u64, @intFromFloat(@round(@as(f64, @floatFromInt(Units_per_second)) * dtime)));
    }

    pub const Num_reserved_props = 32;

    pub const Null = Prop.Null;

    pub const ShapeID = enum(u32) {
        Canopy,
        Cube,
        Disk,
        DistantSphere,
        InfiniteSphere,
        Plane,
        Rectangle,
        Sphere,
    };

    images: List(Image) = .empty,
    materials: List(Material) = .empty,
    shapes: List(Shape),

    num_interpolation_frames: u32 = 0,

    current_time_start: u64 = undefined,

    bvh_builder: PropBvhBuilder,
    light_tree_builder: LightTreeBuilder = .{},

    prop_bvh: PropBvh = .{},
    volume_bvh: PropBvh = .{},

    camera_pos: Vec4f = undefined,
    caustic_aabb: AABB = undefined,

    props: List(Prop),
    prop_world_transformations: List(Transformation),
    prop_parts: List(u32),
    prop_frames: List(u32),
    prop_aabbs: List(AABB),

    lights: List(Light),
    light_aabbs: List(AABB),
    light_cones: List(Vec4f),

    material_ids: List(u32),
    light_ids: List(u32),

    keyframes: List(math.Transformation),

    light_temp_powers: []f32,
    light_distribution: Distribution1D = .{},
    light_tree: LightTree = .{},

    finite_props: List(u32),
    infinite_props: List(u32),

    volumes: List(u32),

    sky: Sky = .{},

    evaluate_visibility: bool = undefined,
    has_volumes: bool = undefined,

    pub fn init(alloc: Allocator) !Scene {
        var shapes = try List(Shape).initCapacity(alloc, 16);
        try shapes.append(alloc, .{ .Canopy = .{} });
        try shapes.append(alloc, .{ .Cube = .{} });
        try shapes.append(alloc, .{ .Disk = .{} });
        try shapes.append(alloc, .{ .DistantSphere = .{} });
        try shapes.append(alloc, .{ .InfiniteSphere = .{} });
        try shapes.append(alloc, .{ .Plane = .{} });
        try shapes.append(alloc, .{ .Rectangle = .{} });
        try shapes.append(alloc, .{ .Sphere = .{} });

        return Scene{
            .shapes = shapes,
            .bvh_builder = try PropBvhBuilder.init(alloc),
            .props = try List(Prop).initCapacity(alloc, Num_reserved_props),
            .prop_world_transformations = try List(Transformation).initCapacity(alloc, Num_reserved_props),
            .prop_parts = try List(u32).initCapacity(alloc, Num_reserved_props),
            .prop_frames = try List(u32).initCapacity(alloc, Num_reserved_props),
            .prop_aabbs = try List(AABB).initCapacity(alloc, Num_reserved_props),
            .lights = try List(Light).initCapacity(alloc, Num_reserved_props),
            .light_aabbs = try List(AABB).initCapacity(alloc, Num_reserved_props),
            .light_cones = try List(Vec4f).initCapacity(alloc, Num_reserved_props),
            .material_ids = try List(u32).initCapacity(alloc, Num_reserved_props),
            .light_ids = try List(u32).initCapacity(alloc, Num_reserved_props),
            .keyframes = try List(math.Transformation).initCapacity(alloc, Num_reserved_props),
            .light_temp_powers = try alloc.alloc(f32, Num_reserved_props),
            .finite_props = try List(u32).initCapacity(alloc, Num_reserved_props),
            .infinite_props = try List(u32).initCapacity(alloc, 3),
            .volumes = try List(u32).initCapacity(alloc, Num_reserved_props),
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
        self.prop_bvh.deinit(alloc);
        self.volume_bvh.deinit(alloc);
        self.bvh_builder.deinit(alloc);

        self.volumes.deinit(alloc);
        self.infinite_props.deinit(alloc);
        self.finite_props.deinit(alloc);

        self.light_tree.deinit(alloc);
        self.light_distribution.deinit(alloc);
        alloc.free(self.light_temp_powers);

        self.keyframes.deinit(alloc);
        self.light_ids.deinit(alloc);
        self.material_ids.deinit(alloc);
        self.light_cones.deinit(alloc);
        self.light_aabbs.deinit(alloc);
        self.lights.deinit(alloc);
        self.prop_aabbs.deinit(alloc);
        self.prop_frames.deinit(alloc);
        self.prop_parts.deinit(alloc);
        self.prop_world_transformations.deinit(alloc);
        self.props.deinit(alloc);

        deinitResources(Shape, alloc, &self.shapes);
        deinitResources(Material, alloc, &self.materials);
        deinitResources(Image, alloc, &self.images);
    }

    pub fn clear(self: *Scene) void {
        self.num_interpolation_frames = 0;

        self.volumes.clearRetainingCapacity();
        self.infinite_props.clearRetainingCapacity();
        self.finite_props.clearRetainingCapacity();
        self.keyframes.clearRetainingCapacity();
        self.light_ids.clearRetainingCapacity();
        self.material_ids.clearRetainingCapacity();
        self.light_cones.clearRetainingCapacity();
        self.light_aabbs.clearRetainingCapacity();
        self.lights.clearRetainingCapacity();
        self.prop_aabbs.clearRetainingCapacity();
        self.prop_frames.clearRetainingCapacity();
        self.prop_parts.clearRetainingCapacity();
        self.prop_world_transformations.clearRetainingCapacity();
        self.props.clearRetainingCapacity();
    }

    pub fn aabb(self: *const Scene) AABB {
        return self.prop_bvh.aabb();
    }

    pub fn causticAabb(self: *const Scene) AABB {
        return self.caustic_aabb;
    }

    pub fn finite(self: *const Scene) bool {
        return 0 == self.infinite_props.items.len;
    }

    pub fn compile(self: *Scene, alloc: Allocator, camera_pos: Vec4f, time: u64, threads: *Threads, fs: *Filesystem) !void {
        self.camera_pos = camera_pos;

        const frames_start = time - (time % Tick_duration);
        self.current_time_start = frames_start;

        self.calculateWorldBounds(camera_pos);

        self.has_volumes = self.volumes.items.len > 0;

        if (self.has_volumes) {
            self.evaluate_visibility = true;
        } else {
            self.evaluate_visibility = false;
            for (self.material_ids.items) |i| {
                if (self.materials.items[i].evaluateVisibility()) {
                    self.evaluate_visibility = true;
                    break;
                }
            }
        }

        try self.sky.compile(alloc, time, self, threads, fs);

        // rebuild prop BVH_builder
        try self.bvh_builder.build(alloc, &self.prop_bvh, self.finite_props.items, self.prop_aabbs.items, threads);
        self.prop_bvh.setProps(self.infinite_props.items, self.props.items, self);

        // rebuild volume BVH
        try self.bvh_builder.build(alloc, &self.volume_bvh, self.volumes.items, self.prop_aabbs.items, threads);
        self.volume_bvh.setProps(&.{}, self.props.items, self);

        const num_lights = self.lights.items.len;
        if (num_lights > self.light_temp_powers.len) {
            self.light_temp_powers = try alloc.realloc(self.light_temp_powers, num_lights);
        }

        for (0..num_lights) |i| {
            self.propPrepareSampling(alloc, i, time, threads);
            self.light_temp_powers[i] = self.lightPower(0, i);
        }

        try self.light_distribution.configure(alloc, self.light_temp_powers[0..num_lights], 0);

        try self.light_tree_builder.build(alloc, &self.light_tree, self, threads);

        var caustic_aabb = math.aabb.Empty;
        for (self.finite_props.items) |i| {
            if (self.props.items[i].caustic()) {
                caustic_aabb.mergeAssign(self.prop_aabbs.items[i]);
            }
        }

        self.caustic_aabb = caustic_aabb;
    }

    pub fn intersect(self: *const Scene, probe: *Probe, frag: *Fragment) bool {
        return self.prop_bvh.intersect(probe, frag, self);
    }

    pub fn visibility(self: *const Scene, probe: *const Probe, sampler: *Sampler, worker: *Worker) ?Vec4f {
        if (self.evaluate_visibility) {
            return self.prop_bvh.visibility(probe, sampler, worker);
        }

        if (self.prop_bvh.intersectP(probe, self)) {
            return null;
        }

        return @as(Vec4f, @splat(1.0));
    }

    pub fn scatter(
        self: *const Scene,
        probe: *Probe,
        frag: *Fragment,
        throughput: *Vec4f,
        sampler: *Sampler,
        worker: *Worker,
    ) bool {
        if (!self.has_volumes) {
            frag.event = .Pass;
            frag.vol_li = @splat(0.0);
            return false;
        }

        return self.volume_bvh.scatter(probe, frag, throughput, sampler, worker);
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

        self.props.items[p].configure(@intFromEnum(ShapeID.Plane), &.{}, self);

        return p;
    }

    pub fn createProp(self: *Scene, alloc: Allocator, shape_id: u32, materials: []const u32) !u32 {
        const p = try self.allocateProp(alloc);

        self.props.items[p].configure(shape_id, materials, self);

        const shape_inst = self.shape(shape_id);
        const num_parts = shape_inst.numParts();

        const parts_start: u32 = @intCast(self.material_ids.items.len);
        self.prop_parts.items[p] = parts_start;

        var i: u32 = 0;
        while (i < num_parts) : (i += 1) {
            try self.material_ids.append(alloc, materials[shape_inst.partIdToMaterialId(i)]);
            try self.light_ids.append(alloc, Null);
        }

        if (shape_inst.finite()) {
            try self.finite_props.append(alloc, p);
        } else {
            try self.infinite_props.append(alloc, p);
        }

        if (self.props.items[p].volume()) {
            try self.volumes.append(alloc, p);
        }

        return p;
    }

    pub fn createPropInstance(self: *Scene, alloc: Allocator, entity: u32) !u32 {
        const p = try self.allocateProp(alloc);

        self.props.items[p] = self.props.items[entity];
        self.prop_parts.items[p] = self.prop_parts.items[entity];

        const shape_inst = self.propShape(p);

        if (shape_inst.finite()) {
            try self.finite_props.append(alloc, p);
        } else {
            try self.infinite_props.append(alloc, p);
        }

        if (self.props.items[p].volume()) {
            try self.volumes.append(alloc, p);
        }

        return p;
    }

    pub fn createLight(self: *Scene, alloc: Allocator, entity: u32) !void {
        const shape_inst = self.propShape(entity);
        const num_parts = shape_inst.numParts();

        var i: u32 = 0;
        while (i < num_parts) : (i += 1) {
            const mat = self.propMaterial(entity, i);
            if (!mat.emissive()) {
                continue;
            }

            if (mat.scatteringVolume()) {
                if (shape_inst.analytical() and mat.emissionMapped()) {
                    try self.allocateLight(alloc, .VolumeImage, false, entity, i);
                } else {
                    try self.allocateLight(alloc, .Volume, false, entity, i);
                }
            } else {
                const two_sided = mat.twoSided();

                if (shape_inst.analytical() and mat.emissionMapped()) {
                    try self.allocateLight(alloc, .PropImage, two_sided, entity, i);
                } else {
                    try self.allocateLight(alloc, .Prop, two_sided, entity, i);
                }
            }
        }
    }

    const Frame = struct {
        f: u32,
        w: f32,
    };

    fn frameAt(self: *const Scene, time: u64) Frame {
        const i = (time - self.current_time_start) / Tick_duration;
        const a_time = self.current_time_start + i * Tick_duration;
        const delta = time - a_time;

        const t: f32 = @floatCast(@as(f64, @floatFromInt(delta)) / @as(f64, @floatFromInt(Tick_duration)));

        return .{ .f = @intCast(i), .w = t };
    }

    pub fn propWorldPosition(self: *const Scene, entity: u32) Vec4f {
        const f = self.prop_frames.items[entity];
        if (Null == f) {
            return self.prop_world_transformations.items[entity].position;
        }

        return self.keyframes.items[f].position;
    }

    pub fn propTransformationAt(self: *const Scene, entity: u32, time: u64) Transformation {
        const f = self.prop_frames.items[entity];
        return self.propTransformationAtMaybeStatic(entity, time, Null == f);
    }

    pub fn propTransformationAtMaybeStatic(self: *const Scene, entity: u32, time: u64, static: bool) Transformation {
        if (static) {
            var trafo = self.prop_world_transformations.items[entity];
            trafo.translate(-self.camera_pos);
            return trafo;
        }

        return self.propAnimatedTransformationAt(self.prop_frames.items[entity], time);
    }

    pub fn propSetWorldTransformation(self: *Scene, entity: u32, t: math.Transformation) void {
        self.prop_world_transformations.items[entity] = Transformation.init(t);
    }

    pub fn propAllocateFrames(self: *Scene, alloc: Allocator, entity: u32) !void {
        const current_len = @as(u32, @intCast(self.keyframes.items.len));
        self.prop_frames.items[entity] = current_len;

        const num_frames = self.num_interpolation_frames;
        try self.keyframes.resize(alloc, current_len + num_frames);

        self.props.items[entity].configureAnimated(self);
    }

    pub fn propHasAnimatedFrames(self: *const Scene, entity: u32) bool {
        return Null != self.prop_frames.items[entity];
    }

    pub fn propSetFrame(self: *Scene, entity: u32, index: u32, frame: math.Transformation) void {
        const b = self.prop_frames.items[entity];

        self.keyframes.items[b + index] = frame;
    }

    pub fn propSetFrames(self: *Scene, entity: u32, frames: [*]const math.Transformation) void {
        const len = self.num_interpolation_frames;
        const b = self.prop_frames.items[entity];
        const e = b + len;

        @memcpy(self.keyframes.items[b..e], frames[0..len]);
    }

    pub fn propSetFramesScale(self: *Scene, entity: u32, scale: Vec4f) void {
        const len = self.num_interpolation_frames;
        const b = self.prop_frames.items[entity];
        const e = b + len;

        for (self.keyframes.items[b..e]) |*f| {
            f.scale = scale;
        }
    }

    pub fn propSetVisibility(self: *Scene, entity: u32, in_camera: bool, in_reflection: bool, in_shadow: bool) void {
        self.props.items[entity].setVisibility(in_camera, in_reflection, in_shadow);
    }

    fn propPrepareSampling(self: *Scene, alloc: Allocator, light_id: usize, time: u64, threads: *Threads) void {
        var l = &self.lights.items[light_id];

        const entity = l.prop;
        const part = l.part;

        const shape_inst = self.propShape(entity);

        const p = self.prop_parts.items[entity] + part;

        self.light_ids.items[p] = @intCast(light_id);

        const m = self.material_ids.items[p];
        const mat = &self.materials.items[m];

        const variant = shape_inst.prepareSampling(alloc, entity, part, m, &self.light_tree_builder, self, threads) catch 0;
        l.variant = variant;

        const trafo = self.propTransformationAt(entity, time);
        const extent = if (l.volumetric()) shape_inst.volume(trafo.scale()) else shape_inst.area(part, trafo.scale());

        const average_radiance = mat.prepareSampling(alloc, shape_inst, part, trafo, extent, self, threads);

        const f = self.prop_frames.items[entity];
        const part_aabb = shape_inst.partAabb(part, variant);
        const part_cone = shape_inst.partCone(part, variant);

        if (Null == f) {
            var bb = part_aabb.transform(trafo.objectToWorld());
            bb.cacheRadius();

            self.light_aabbs.items[light_id] = bb;

            const tc = trafo.objectToWorldNormal(part_cone);
            self.light_cones.items[light_id] = Vec4f{ tc[0], tc[1], tc[2], part_cone[3] };
        } else {
            const frames = self.keyframes.items.ptr + f;

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
                var j: u32 = Num_steps - 1;
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

        self.light_aabbs.items[light_id].bounds[0][3] = math.hmax3(
            self.lights.items[light_id].power(average_radiance, extent, self.aabb(), self),
        );
    }

    pub fn propAabbIntersect(self: *const Scene, entity: u32, ray: math.Ray) bool {
        return self.prop_aabbs.items[entity].intersect(ray);
    }

    pub fn propAabbIntersectP(self: *const Scene, entity: u32, ray: math.Ray) ?f32 {
        return self.prop_aabbs.items[entity].intersectP(ray);
    }

    pub fn propRadius(self: *const Scene, entity: u32) f32 {
        return self.prop_aabbs.items[entity].cachedRadius();
    }

    pub fn propShape(self: *const Scene, entity: usize) *Shape {
        return &self.shapes.items[self.props.items[entity].shape];
    }

    pub fn propMaterialId(self: *const Scene, entity: u32, part: u32) u32 {
        const p = self.prop_parts.items[entity] + part;
        return self.material_ids.items[p];
    }

    pub fn propMaterial(self: *const Scene, entity: u32, part: u32) *Material {
        const p = self.prop_parts.items[entity] + part;
        return &self.materials.items[self.material_ids.items[p]];
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

    pub fn prop(self: *const Scene, index: u32) Prop {
        return self.props.items[index];
    }

    pub fn numLights(self: *const Scene) u32 {
        return @intCast(self.lights.items.len);
    }

    pub fn light(self: *const Scene, id: u32) Light {
        return self.lights.items[id];
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

    pub fn lightPdfSpatial(self: *const Scene, id: u32, p: Vec4f, n: Vec4f, total_sphere: bool, split_threshold: f32) f32 {
        // _ = p;
        // _ = n;
        // _ = total_sphere;
        // _ = split;

        // const pdf = self.light_distribution.pdfI(id);
        // return .{ .offset = id, .pdf = pdf };

        return self.light_tree.pdf(p, n, total_sphere, split_threshold, id, self);
    }

    pub fn lightTwoSided(self: *const Scene, variant: u32, light_id: u32) bool {
        _ = variant;
        return self.lights.items[light_id].two_sided;
    }

    pub fn lightPower(self: *const Scene, variant: u32, light_id: usize) f32 {
        _ = variant;
        return self.light_aabbs.items[light_id].bounds[0][3];
    }

    pub fn lightAabb(self: *const Scene, light_id: u32) AABB {
        return self.light_aabbs.items[light_id];
    }

    pub fn lightCone(self: *const Scene, light_id: u32) Vec4f {
        return self.light_cones.items[light_id];
    }

    pub fn lightProperties(self: *const Scene, light_id: u32, variant: u32) LightProperties {
        _ = variant;

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
        try self.prop_world_transformations.append(alloc, undefined);
        try self.prop_parts.append(alloc, 0);
        try self.prop_frames.append(alloc, Null);
        try self.prop_aabbs.append(alloc, undefined);

        return @intCast(self.props.items.len - 1);
    }

    fn allocateLight(self: *Scene, alloc: Allocator, class: Light.Class, two_sided: bool, entity: u32, part: u32) !void {
        try self.lights.append(alloc, .{ .class = class, .two_sided = two_sided, .prop = entity, .part = part, .variant = undefined });
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
        for (self.prop_frames.items, 0..) |f, entity| {
            const shape_aabb = self.propShape(entity).aabb();

            var bounds: AABB = undefined;

            if (Null == f) {
                const trafo = self.prop_world_transformations.items[entity];

                bounds = shape_aabb.transform(trafo.objectToWorld());
            } else {
                const frames = self.keyframes.items.ptr + f;

                bounds = shape_aabb.transform(frames[0].toMat4x4());

                var i: u32 = 0;
                const len = self.num_interpolation_frames - 1;
                while (i < len) : (i += 1) {
                    const a = frames[i];
                    const b = frames[i + 1];

                    var t = Interval;
                    var j: u32 = Num_steps - 1;
                    while (j > 0) : (j -= 1) {
                        const inter = a.lerp(b, t);
                        bounds.mergeAssign(shape_aabb.transform(inter.toMat4x4()));
                        t += Interval;
                    }
                }

                bounds.mergeAssign(shape_aabb.transform(frames[len].toMat4x4()));
            }

            bounds.translate(-camera_pos);
            bounds.cacheRadius();
            self.prop_aabbs.items[entity] = bounds;
        }
    }

    fn propAnimatedTransformationAt(self: *const Scene, frames_id: u32, time: u64) Transformation {
        const f = self.frameAt(time);

        const frames = self.keyframes.items.ptr + frames_id;

        const a = frames[f.f];
        const b = frames[f.f + 1];

        var inter = a.lerp(b, f.w);
        inter.position -= self.camera_pos;

        return Transformation.init(inter);
    }

    fn countFrames(frame_step: u64, frame_duration: u64) u32 {
        const a: u32 = @max(@as(u32, @intCast(frame_duration / Tick_duration)), 1);
        const b: u32 = if (matching(frame_step, Tick_duration)) 0 else 1;
        const c: u32 = if (matching(frame_duration, Tick_duration)) 0 else 1;

        return a + b + c;
    }

    fn matching(a: u64, b: u64) bool {
        return 0 == (if (a > b) a % b else (if (0 == a) 0 else b % a));
    }
};
