const cnst = @import("constants.zig");
const Prop = @import("prop/prop.zig").Prop;
const PropBvh = @import("prop/tree.zig").Tree;
const PropBvhBuilder = @import("prop/builder.zig").Builder;
const Light = @import("light/light.zig").Light;
const Image = @import("../image/image.zig").Image;
const Intersection = @import("prop/intersection.zig").Intersection;
const Interpolation = @import("shape/intersection.zig").Interpolation;
const Material = @import("material/material.zig").Material;
const anim = @import("animation/animation.zig");
const Animation = anim.Animation;
const Keyframe = anim.Keyframe;
const shp = @import("shape/shape.zig");
const Shape = shp.Shape;
const Ray = @import("ray.zig").Ray;
const Filter = @import("../image/texture/sampler.zig").Filter;
const Worker = @import("worker.zig").Worker;
const Transformation = @import("composed_transformation.zig").ComposedTransformation;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;
const Distribution1D = math.Distribution1D;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;
const ALU = std.ArrayListUnmanaged;

const Tick_duration = cnst.Units_per_second / 60;
const Num_steps = 4;
const Interval = 1.0 / @intToFloat(f32, Num_steps);

const Num_reserved_props = 32;

const LightPick = Distribution1D.Discrete;

pub const Scene = struct {
    images: *ALU(Image),
    materials: *ALU(Material),
    shapes: *ALU(Shape),

    null_shape: u32,

    num_interpolation_frames: u32 = 0,

    current_time_start: u64 = undefined,

    bvh_builder: PropBvhBuilder = undefined,

    prop_bvh: PropBvh = .{},
    volume_bvh: PropBvh = .{},

    props: ALU(Prop),
    prop_world_transformations: ALU(Transformation),
    prop_world_positions: ALU(Vec4f),
    prop_parts: ALU(u32),
    prop_frames: ALU(u32),
    prop_topology: ALU(Prop.Topology),
    prop_aabbs: ALU(AABB),

    lights: ALU(Light),
    light_aabbs: ALU(AABB),

    material_ids: ALU(u32),
    light_ids: ALU(u32),

    keyframes: ALU(math.Transformation),
    animations: ALU(Animation),

    light_temp_powers: []f32 = &.{},
    light_distribution: Distribution1D = .{},

    finite_props: ALU(u32),
    infinite_props: ALU(u32),

    volumes: ALU(u32),

    has_tinted_shadow: bool = undefined,
    has_volumes: bool = undefined,

    pub fn init(
        alloc: *Allocator,
        images: *ALU(Image),
        materials: *ALU(Material),
        shapes: *ALU(Shape),
        null_shape: u32,
    ) !Scene {
        return Scene{
            .bvh_builder = try PropBvhBuilder.init(alloc),
            .images = images,
            .materials = materials,
            .shapes = shapes,
            .null_shape = null_shape,
            .props = try ALU(Prop).initCapacity(alloc, Num_reserved_props),
            .prop_world_transformations = try ALU(Transformation).initCapacity(alloc, Num_reserved_props),
            .prop_world_positions = try ALU(Vec4f).initCapacity(alloc, Num_reserved_props),
            .prop_parts = try ALU(u32).initCapacity(alloc, Num_reserved_props),
            .prop_frames = try ALU(u32).initCapacity(alloc, Num_reserved_props),
            .prop_topology = try ALU(Prop.Topology).initCapacity(alloc, Num_reserved_props),
            .prop_aabbs = try ALU(AABB).initCapacity(alloc, Num_reserved_props),
            .lights = try ALU(Light).initCapacity(alloc, Num_reserved_props),
            .light_aabbs = try ALU(AABB).initCapacity(alloc, Num_reserved_props),
            .material_ids = try ALU(u32).initCapacity(alloc, Num_reserved_props),
            .light_ids = try ALU(u32).initCapacity(alloc, Num_reserved_props),
            .keyframes = try ALU(math.Transformation).initCapacity(alloc, Num_reserved_props),
            .animations = try ALU(Animation).initCapacity(alloc, Num_reserved_props),
            .finite_props = try ALU(u32).initCapacity(alloc, Num_reserved_props),
            .infinite_props = try ALU(u32).initCapacity(alloc, 3),
            .volumes = try ALU(u32).initCapacity(alloc, Num_reserved_props),
        };
    }

    pub fn deinit(self: *Scene, alloc: *Allocator) void {
        self.prop_bvh.deinit(alloc);
        self.volume_bvh.deinit(alloc);
        self.bvh_builder.deinit(alloc);

        self.volumes.deinit(alloc);
        self.infinite_props.deinit(alloc);
        self.finite_props.deinit(alloc);

        self.light_distribution.deinit(alloc);
        alloc.free(self.light_temp_powers);

        for (self.animations.items) |*a| {
            a.deinit(alloc);
        }
        self.animations.deinit(alloc);
        self.keyframes.deinit(alloc);
        self.light_ids.deinit(alloc);
        self.material_ids.deinit(alloc);
        self.light_aabbs.deinit(alloc);
        self.lights.deinit(alloc);
        self.prop_aabbs.deinit(alloc);
        self.prop_topology.deinit(alloc);
        self.prop_frames.deinit(alloc);
        self.prop_parts.deinit(alloc);
        self.prop_world_positions.deinit(alloc);
        self.prop_world_transformations.deinit(alloc);
        self.props.deinit(alloc);
    }

    pub fn aabb(self: Scene) AABB {
        return self.prop_bvh.aabb();
    }

    pub fn simulate(
        self: *Scene,
        alloc: *Allocator,
        camera_pos: Vec4f,
        start: u64,
        end: u64,
        threads: *Threads,
    ) !void {
        const frames_start = start - (start % Tick_duration);
        const end_rem = end % Tick_duration;
        const frames_end = end + (if (end_rem > 0) Tick_duration - end_rem else 0);

        self.current_time_start = frames_start;

        for (self.animations.items) |*a| {
            a.resample(frames_start, frames_end, Tick_duration);
            a.update(self);
        }

        try self.compile(alloc, camera_pos, start, threads);
    }

    fn compile(
        self: *Scene,
        alloc: *Allocator,
        camera_pos: Vec4f,
        time: u64,
        threads: *Threads,
    ) !void {
        self.has_tinted_shadow = false;

        for (self.props.items) |p, i| {
            self.propCalculateWorldTransformation(i, camera_pos);

            self.has_tinted_shadow = self.has_tinted_shadow or p.hasTintedShadow();
        }

        for (self.volumes.items) |v| {
            self.props.items[v].setVisibleInShadow(false);
        }

        // rebuild prop BVH_builder
        try self.bvh_builder.build(alloc, &self.prop_bvh, self.finite_props.items, self.prop_aabbs.items, threads);
        self.prop_bvh.setProps(self.infinite_props.items, self.props.items);

        // rebuild volume BVH
        try self.bvh_builder.build(alloc, &self.volume_bvh, self.volumes.items, self.prop_aabbs.items, threads);
        self.volume_bvh.setProps(&.{}, self.props.items);

        self.light_temp_powers = try alloc.realloc(self.light_temp_powers, self.lights.items.len);

        for (self.lights.items) |l, i| {
            l.prepareSampling(alloc, i, time, self, threads);

            self.light_temp_powers[i] = self.lightPower(0, i);
        }

        try self.light_distribution.configure(alloc, self.light_temp_powers, 0);

        self.has_volumes = self.volumes.items.len > 0;
    }

    pub fn intersect(self: Scene, ray: *Ray, worker: *Worker, ipo: Interpolation, isec: *Intersection) bool {
        return self.prop_bvh.intersect(ray, worker, ipo, isec);
    }

    pub fn intersectVolume(self: Scene, ray: *Ray, worker: *Worker, isec: *Intersection) bool {
        return self.volume_bvh.intersect(ray, worker, .NoTangentSpace, isec);
    }

    pub fn intersectP(self: Scene, ray: Ray, worker: *Worker) bool {
        return self.prop_bvh.intersectP(ray, worker);
    }

    pub fn visibility(self: Scene, ray: Ray, filter: ?Filter, worker: *Worker) ?Vec4f {
        if (self.has_tinted_shadow) {
            return self.prop_bvh.visibility(ray, filter, worker);
        }

        if (self.prop_bvh.intersectP(ray, worker)) {
            return null;
        }

        return @splat(4, @as(f32, 1.0));
    }

    pub fn calculateNumInterpolationFrames(self: *Scene, frame_step: u64, frame_duration: u64) void {
        self.num_interpolation_frames = countFrames(frame_step, frame_duration) + 1;
    }

    pub fn createEntity(self: *Scene, alloc: *Allocator) !u32 {
        const p = try self.allocateProp(alloc);

        self.props.items[p].configure(self.null_shape, &.{}, self.*);

        return p;
    }

    pub fn createProp(self: *Scene, alloc: *Allocator, shape_id: u32, materials: []const u32) !u32 {
        const p = self.allocateProp(alloc) catch return Prop.Null;

        self.props.items[p].configure(shape_id, materials, self.*);

        const shape_inst = self.shape(shape_id);
        const num_parts = shape_inst.numParts();

        // This calls a very simple test to check whether the prop added just before this one
        // has the same shape, same materials, and is not a light.
        if (self.propIsInstance(shape_id, materials, num_parts)) {
            self.prop_parts.items[p] = self.prop_parts.items[self.props.items.len - 2];
        } else {
            const parts_start = @intCast(u32, self.material_ids.items.len);
            self.prop_parts.items[p] = parts_start;

            var i: u32 = 0;
            while (i < num_parts) : (i += 1) {
                try self.material_ids.append(alloc, materials[shape_inst.partIdToMaterialId(i)]);
                try self.light_ids.append(alloc, Prop.Null);
            }
        }

        if (shape_inst.isFinite()) {
            try self.finite_props.append(alloc, p);
        } else {
            try self.infinite_props.append(alloc, p);
        }

        // Shape has no surface
        if (1 == num_parts and 1.0 == self.material(materials[0]).ior()) {
            if (shape_inst.isFinite()) {
                try self.volumes.append(alloc, p);
            }
        }

        return p;
    }

    pub fn createLight(self: *Scene, alloc: *Allocator, entity: u32) !void {
        const shape_inst = self.propShape(entity);

        var i: u32 = 0;
        const len = shape_inst.numParts();
        while (i < len) : (i += 1) {
            const mat = self.propMaterial(entity, i);
            if (!mat.isEmissive()) {
                continue;
            }

            const two_sided = mat.isTwoSided();

            if (shape_inst.isAnalytical() and mat.hasEmissionMap()) {
                try self.allocateLight(alloc, .PropImage, two_sided, entity, i);
            } else {
                try self.allocateLight(alloc, .Prop, two_sided, entity, i);
            }
        }
    }

    const Frame = struct {
        f: u32,
        w: f32,
    };

    fn frameAt(self: Scene, time: u64) Frame {
        const i = (time - self.current_time_start) / Tick_duration;
        const a_time = self.current_time_start + i * Tick_duration;
        const delta = time - a_time;

        const t = @floatCast(f32, @intToFloat(f64, delta) / @intToFloat(f64, Tick_duration));

        return .{ .f = @intCast(u32, i), .w = t };
    }

    pub fn propWorldPosition(self: Scene, entity: u32) Vec4f {
        return self.prop_world_positions.items[entity];
    }

    pub fn propTransformationAt(self: Scene, entity: usize, time: u64) Transformation {
        const f = self.prop_frames.items[entity];

        if (Prop.Null == f) {
            return self.prop_world_transformations.items[entity];
        }

        return self.propAnimatedTransformationAt(self.prop_frames.items[entity], time);
    }

    pub fn propTransformationAtMaybeStatic(self: Scene, entity: usize, time: u64, static: bool) Transformation {
        if (static) {
            return self.prop_world_transformations.items[entity];
        }

        return self.propAnimatedTransformationAt(self.prop_frames.items[entity], time);
    }

    pub fn propSetTransformation(self: *Scene, entity: u32, t: math.Transformation) void {
        const f = self.prop_frames.items[entity];
        self.keyframes.items[f + self.num_interpolation_frames] = t;
    }

    pub fn propSetWorldTransformation(self: *Scene, entity: u32, t: math.Transformation) void {
        self.prop_world_transformations.items[entity].prepare(t);
        self.prop_world_positions.items[entity] = t.position;
    }

    pub fn propSerializeChild(self: *Scene, alloc: *Allocator, parent_id: u32, child_id: u32) !void {
        self.props.items[child_id].setHasParent();

        if (self.propHasAnimatedFrames(parent_id) and !self.propHasAnimatedFrames(child_id)) {
            // This is the case if child has no animation attached to it directly
            try self.propAllocateFrames(alloc, child_id, false);
        }

        const pt = &self.prop_topology.items[parent_id];
        if (Prop.Null == pt.child) {
            pt.child = child_id;
        } else {
            self.prop_topology.items[self.prop_topology.items.len - 2].next = child_id;
        }
    }

    pub fn propAllocateFrames(self: *Scene, alloc: *Allocator, entity: u32, local_animation: bool) !void {
        self.prop_frames.items[entity] = @intCast(u32, self.keyframes.items.len);

        const num_world_frames = self.num_interpolation_frames;
        const num_local_frames = if (local_animation) num_world_frames else 1;
        const num_frames = num_world_frames + num_local_frames;

        var i: u32 = 0;
        while (i < num_frames) : (i += 1) {
            try self.keyframes.append(alloc, .{});
        }

        self.props.items[entity].configureAnimated(local_animation, self.*);
    }

    pub fn propHasAnimatedFrames(self: Scene, entity: u32) bool {
        return Prop.Null != self.prop_frames.items[entity];
    }

    pub fn propSetFrames(self: *Scene, entity: u32, frames: [*]math.Transformation) void {
        const num_frames = self.num_interpolation_frames;
        const f = self.prop_frames.items[entity];

        const b = f + num_frames;
        const e = b + num_frames;
        const local_frames = self.keyframes.items[b..e];

        for (local_frames) |*lf, i| {
            lf.* = frames[i];
        }
    }

    pub fn propSetVisibility(self: *Scene, entity: u32, in_camera: bool, in_reflection: bool, in_shadow: bool) void {
        self.props.items[entity].setVisibility(in_camera, in_reflection, in_shadow);
    }

    pub fn propPrepareSampling(
        self: *Scene,
        alloc: *Allocator,
        entity: u32,
        part: u32,
        light_id: usize,
        time: u64,
        threads: *Threads,
    ) void {
        var shape_inst = self.propShape(entity);

        const p = self.prop_parts.items[entity] + part;

        self.light_ids.items[p] = @intCast(u32, light_id);

        const m = self.material_ids.items[p];

        shape_inst.prepareSampling(part);

        const trafo = self.propTransformationAt(entity, time);
        const scale = trafo.scale();

        const extent = shape_inst.area(part, scale);

        self.lights.items[light_id].extent = extent;

        const mat = &self.materials.items[m];
        const average_radiance = mat.prepareSampling(alloc, shape_inst, part, trafo, extent, self.*, threads);

        self.light_aabbs.items[light_id].bounds[1][3] = math.maxComponent3(
            self.lights.items[light_id].power(average_radiance, self.aabb(), self.*),
        );
    }

    pub fn propAabbIntersectP(self: Scene, entity: usize, ray: Ray) bool {
        return self.prop_aabbs.items[entity].intersectP(ray.ray);
    }

    pub fn propShape(self: Scene, entity: usize) Shape {
        return self.shapes.items[self.props.items[entity].shape];
    }

    pub fn propMaterial(self: Scene, entity: usize, part: u32) Material {
        const p = self.prop_parts.items[entity] + part;
        return self.materials.items[self.material_ids.items[p]];
    }

    pub fn propTopology(self: Scene, entity: usize) Prop.Topology {
        return self.prop_topology.items[entity];
    }

    pub fn propLightId(self: Scene, entity: u32, part: u32) u32 {
        const p = self.prop_parts.items[entity] + part;
        return self.light_ids.items[p];
    }

    pub fn image(self: Scene, image_id: u32) Image {
        return self.images.items[image_id];
    }

    pub fn material(self: Scene, material_id: u32) Material {
        return self.materials.items[material_id];
    }

    pub fn shape(self: Scene, shape_id: u32) Shape {
        return self.shapes.items[shape_id];
    }

    pub fn prop(self: Scene, index: u32) Prop {
        return self.props.items[index];
    }

    pub fn light(self: Scene, id: u32) Light {
        return self.lights.items[id];
    }

    pub fn randomLight(
        self: Scene,
        p: Vec4f,
        n: Vec4f,
        total_sphere: bool,
        random: f32,
        split: bool,
        buffer: *Worker.Lights,
    ) []LightPick {
        _ = p;
        _ = n;
        _ = total_sphere;
        _ = split;

        buffer[0] = self.light_distribution.sampleDiscrete(random);

        return buffer[0..1];
    }

    pub fn lightPdf(self: Scene, id: u32, p: Vec4f, n: Vec4f, total_sphere: bool, split: bool) LightPick {
        _ = p;
        _ = n;
        _ = total_sphere;
        _ = split;

        const pdf = self.light_distribution.pdfI(id);

        return .{ .offset = id, .pdf = pdf };
    }

    pub fn lightArea(self: Scene, entity: u32, part: u32) f32 {
        const p = self.prop_parts.items[entity] + part;
        const light_id = self.light_ids.items[p];

        if (Prop.Null == light_id) {
            return 1.0;
        }

        return self.lights.items[light_id].extent;
    }

    pub fn lightPower(self: Scene, variant: u32, light_id: usize) f32 {
        _ = variant;

        return self.light_aabbs.items[light_id].bounds[1][3];
    }

    fn allocateProp(self: *Scene, alloc: *Allocator) !u32 {
        try self.props.append(alloc, .{});
        try self.prop_world_transformations.append(alloc, .{});
        try self.prop_world_positions.append(alloc, .{});
        try self.prop_parts.append(alloc, 0);
        try self.prop_frames.append(alloc, Prop.Null);
        try self.prop_topology.append(alloc, .{});
        try self.prop_aabbs.append(alloc, .{});

        return @intCast(u32, self.props.items.len - 1);
    }

    fn allocateLight(
        self: *Scene,
        alloc: *Allocator,
        typef: Light.Type,
        two_sided: bool,
        entity: u32,
        part: u32,
    ) !void {
        try self.lights.append(alloc, .{ .typef = typef, .two_sided = two_sided, .prop = entity, .part = part });

        try self.light_aabbs.append(alloc, AABB.init(@splat(4, @as(f32, 0.0)), @splat(4, @as(f32, 0.0))));
    }

    fn propIsInstance(self: Scene, shape_id: u32, materials: []const u32, num_parts: u32) bool {
        const num_props = self.props.items.len;
        if (num_props < 2 or self.props.items[num_props - 2].shape != shape_id) {
            return false;
        }

        const shape_inst = self.shape(shape_id);

        const p = self.prop_parts.items[num_props - 2];
        var i: u32 = 0;
        while (i < num_parts) : (i += 1) {
            const m = materials[shape_inst.partIdToMaterialId(i)];

            if (m != self.material_ids.items[p + i]) {
                return false;
            }

            if (self.materials.items[m].isEmissive()) {
                return false;
            }
        }

        return true;
    }

    pub fn createAnimation(self: *Scene, alloc: *Allocator, entity: u32, count: u32) !u32 {
        try self.animations.append(alloc, try Animation.init(alloc, entity, count, self.num_interpolation_frames));

        try self.propAllocateFrames(alloc, entity, true);

        return @intCast(u32, self.animations.items.len - 1);
    }

    pub fn animationSetFrame(self: *Scene, animation: u32, index: usize, keyframe: Keyframe) void {
        self.animations.items[animation].set(index, keyframe);
    }

    fn propCalculateWorldTransformation(self: *Scene, entity: usize, camera_pos: Vec4f) void {
        if (self.props.items[entity].hasNoParent()) {
            const f = self.prop_frames.items[entity];

            if (Prop.Null != f) {
                const frames = self.keyframes.items.ptr + f;

                var i: u32 = 0;
                const len = self.num_interpolation_frames;
                while (i < len) : (i += 1) {
                    frames[i].set(frames[len + i], camera_pos);
                }
            }

            self.propPropagateTransformation(entity, camera_pos);
        }
    }

    fn propPropagateTransformation(self: *Scene, entity: usize, camera_pos: Vec4f) void {
        const f = self.prop_frames.items[entity];

        const shape_aabb = self.propShape(entity).aabb();

        if (Prop.Null == f) {
            var trafo = &self.prop_world_transformations.items[entity];

            trafo.setPosition(self.prop_world_positions.items[entity] - camera_pos);

            self.prop_aabbs.items[entity] = shape_aabb.transform(trafo.objectToWorld());

            var child = self.propTopology(entity).child;
            while (Prop.Null != child) {
                self.propInheritTransformation(child, trafo.*, camera_pos);

                child = self.propTopology(child).next;
            }
        } else {
            const frames = self.keyframes.items.ptr + f;

            var bounds = shape_aabb.transform(frames[0].toMat4x4());

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

            self.prop_aabbs.items[entity] = bounds;

            var child = self.propTopology(entity).child;
            while (Prop.Null != child) {
                self.propInheritTransformations(child, frames, camera_pos);

                child = self.propTopology(child).next;
            }
        }
    }

    fn propInheritTransformation(
        self: *Scene,
        entity: u32,
        trafo: Transformation,
        camera_pos: Vec4f,
    ) void {
        const f = self.prop_frames.items[entity];

        if (Prop.Null != f) {
            const frames = self.keyframes.items.ptr + f;

            const local_animation = self.prop(entity).hasLocalAnimation();

            var i: u32 = 0;
            const len = self.num_interpolation_frames;
            while (i < len) : (i += 1) {
                const lf = if (local_animation) i else 0;
                frames[i] = trafo.transform(frames[len + lf]);
            }
        }

        self.propPropagateTransformation(entity, camera_pos);
    }

    fn propInheritTransformations(
        self: *Scene,
        entity: u32,
        frames: [*]math.Transformation,
        camera_pos: Vec4f,
    ) void {
        const local_animation = self.prop(entity).hasLocalAnimation();

        const tf = self.keyframes.items.ptr + self.prop_frames.items[entity];

        var i: u32 = 0;
        const len = self.num_interpolation_frames;
        while (i < len) : (i += 1) {
            const lf = if (local_animation) i else 0;
            tf[i] = frames[i].transform(tf[len + lf]);
        }

        self.propPropagateTransformation(entity, camera_pos);
    }

    fn propAnimatedTransformationAt(self: Scene, frames_id: u32, time: u64) Transformation {
        const f = self.frameAt(time);

        const frames = self.keyframes.items.ptr + frames_id;

        const a = frames[f.f];
        const b = frames[f.f + 1];

        return Transformation.init(a.lerp(b, f.w));
    }

    fn countFrames(frame_step: u64, frame_duration: u64) u32 {
        const a: u32 = std.math.max(@intCast(u32, frame_duration / Tick_duration), 1);
        const b: u32 = if (matching(frame_step, Tick_duration)) 0 else 1;
        const c: u32 = if (matching(frame_duration, Tick_duration)) 0 else 1;

        return a + b + c;
    }

    fn matching(a: u64, b: u64) bool {
        return 0 == (if (a > b) a % b else (if (0 == a) 0 else b % a));
    }
};
