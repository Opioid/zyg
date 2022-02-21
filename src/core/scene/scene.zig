pub const cnst = @import("constants.zig");
pub const Prop = @import("prop/prop.zig").Prop;
const PropBvh = @import("prop/tree.zig").Tree;
const PropBvhBuilder = @import("prop/builder.zig").Builder;
const Light = @import("light/light.zig").Light;
const LightTree = @import("light/tree.zig").Tree;
const LightTreeBuilder = @import("light/tree_builder.zig").Builder;
const Image = @import("../image/image.zig").Image;
const Intersection = @import("prop/intersection.zig").Intersection;
const Interpolation = @import("shape/intersection.zig").Interpolation;
pub const Material = @import("material/material.zig").Material;
const shp = @import("shape/shape.zig");
pub const Shape = shp.Shape;
const Ray = @import("ray.zig").Ray;
const Filter = @import("../image/texture/sampler.zig").Filter;
const Worker = @import("worker.zig").Worker;
pub const Transformation = @import("composed_transformation.zig").ComposedTransformation;
const Sky = @import("../sky/sky.zig").Sky;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;
const Distribution1D = math.Distribution1D;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;
const ALU = std.ArrayListUnmanaged;

const LightPick = Distribution1D.Discrete;

pub const Scene = struct {
    pub const Tick_duration = cnst.Units_per_second / 60;
    const Num_steps = 4;
    const Interval = 1.0 / @intToFloat(f32, Num_steps);

    pub const Num_reserved_props = 32;

    pub const Null = Prop.Null;

    pub const ShapeID = enum(u32) {
        Null,
        Canopy,
        Cube,
        Disk,
        DistantSphere,
        InfiniteSphere,
        Plane,
        Rectangle,
        Sphere,
    };

    images: ALU(Image) = .{},
    materials: ALU(Material) = .{},
    shapes: ALU(Shape),

    num_interpolation_frames: u32 = 0,

    current_time_start: u64 = undefined,

    bvh_builder: PropBvhBuilder,
    light_tree_builder: LightTreeBuilder = .{},

    prop_bvh: PropBvh = .{},
    volume_bvh: PropBvh = .{},

    caustic_aabb: AABB = undefined,

    props: ALU(Prop),
    prop_world_transformations: ALU(Transformation),
    prop_world_positions: ALU(Vec4f),
    prop_parts: ALU(u32),
    prop_frames: ALU(u32),
    prop_aabbs: ALU(AABB),

    lights: ALU(Light),
    light_aabbs: ALU(AABB),
    light_cones: ALU(Vec4f),

    material_ids: ALU(u32),
    light_ids: ALU(u32),

    keyframes: ALU(math.Transformation),

    light_temp_powers: []f32 = &.{},
    light_distribution: Distribution1D = .{},
    light_tree: LightTree = .{},

    finite_props: ALU(u32),
    infinite_props: ALU(u32),

    volumes: ALU(u32),

    sky: ?Sky = null,

    tinted_shadow: bool = undefined,
    has_volumes: bool = undefined,

    pub fn init(alloc: Allocator) !Scene {
        var shapes = try ALU(Shape).initCapacity(alloc, 16);
        try shapes.append(alloc, Shape{ .Null = {} });
        try shapes.append(alloc, Shape{ .Canopy = .{} });
        try shapes.append(alloc, Shape{ .Cube = .{} });
        try shapes.append(alloc, Shape{ .Disk = .{} });
        try shapes.append(alloc, Shape{ .DistantSphere = .{} });
        try shapes.append(alloc, Shape{ .InfiniteSphere = .{} });
        try shapes.append(alloc, Shape{ .Plane = .{} });
        try shapes.append(alloc, Shape{ .Rectangle = .{} });
        try shapes.append(alloc, Shape{ .Sphere = .{} });

        return Scene{
            .shapes = shapes,
            .bvh_builder = try PropBvhBuilder.init(alloc),
            .props = try ALU(Prop).initCapacity(alloc, Num_reserved_props),
            .prop_world_transformations = try ALU(Transformation).initCapacity(alloc, Num_reserved_props),
            .prop_world_positions = try ALU(Vec4f).initCapacity(alloc, Num_reserved_props),
            .prop_parts = try ALU(u32).initCapacity(alloc, Num_reserved_props),
            .prop_frames = try ALU(u32).initCapacity(alloc, Num_reserved_props),
            .prop_aabbs = try ALU(AABB).initCapacity(alloc, Num_reserved_props),
            .lights = try ALU(Light).initCapacity(alloc, Num_reserved_props),
            .light_aabbs = try ALU(AABB).initCapacity(alloc, Num_reserved_props),
            .light_cones = try ALU(Vec4f).initCapacity(alloc, Num_reserved_props),
            .material_ids = try ALU(u32).initCapacity(alloc, Num_reserved_props),
            .light_ids = try ALU(u32).initCapacity(alloc, Num_reserved_props),
            .keyframes = try ALU(math.Transformation).initCapacity(alloc, Num_reserved_props),
            .finite_props = try ALU(u32).initCapacity(alloc, Num_reserved_props),
            .infinite_props = try ALU(u32).initCapacity(alloc, 3),
            .volumes = try ALU(u32).initCapacity(alloc, Num_reserved_props),
        };
    }

    fn deinitResources(comptime T: type, alloc: Allocator, resources: *ALU(T)) void {
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
        self.prop_world_positions.deinit(alloc);
        self.prop_world_transformations.deinit(alloc);
        self.props.deinit(alloc);

        deinitResources(Shape, alloc, &self.shapes);
        deinitResources(Material, alloc, &self.materials);
        deinitResources(Image, alloc, &self.images);
    }

    pub fn clear(self: *Scene) void {
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
        self.prop_world_positions.clearRetainingCapacity();
        self.prop_world_transformations.clearRetainingCapacity();
        self.props.clearRetainingCapacity();
    }

    pub fn aabb(self: Scene) AABB {
        return self.prop_bvh.aabb();
    }

    pub fn causticAabb(self: Scene) AABB {
        return self.caustic_aabb;
    }

    pub fn finite(self: Scene) bool {
        return 0 == self.infinite_props.items.len;
    }

    pub fn compile(
        self: *Scene,
        alloc: Allocator,
        camera_pos: Vec4f,
        time: u64,
        worker: Worker,
        threads: *Threads,
    ) !void {
        const frames_start = time - (time % Tick_duration);
        self.current_time_start = frames_start;

        self.tinted_shadow = false;

        for (self.props.items) |p, i| {
            self.propCalculateWorldTransformation(i, camera_pos);

            self.tinted_shadow = self.tinted_shadow or p.tintedShadow();
        }

        for (self.volumes.items) |v| {
            self.props.items[v].setVisibleInShadow(false);
        }

        if (self.sky) |*sky| {
            sky.compile(alloc, time, self, threads);
        }

        // rebuild prop BVH_builder
        try self.bvh_builder.build(alloc, &self.prop_bvh, self.finite_props.items, self.prop_aabbs.items, threads);
        self.prop_bvh.setProps(self.infinite_props.items, self.props.items);

        // rebuild volume BVH
        try self.bvh_builder.build(alloc, &self.volume_bvh, self.volumes.items, self.prop_aabbs.items, threads);
        self.volume_bvh.setProps(&.{}, self.props.items);

        self.light_temp_powers = try alloc.realloc(self.light_temp_powers, self.lights.items.len);

        for (self.lights.items) |l, i| {
            l.prepareSampling(alloc, i, time, self, worker, threads);

            self.light_temp_powers[i] = self.lightPower(0, i);
        }

        try self.light_distribution.configure(alloc, self.light_temp_powers, 0);

        try self.light_tree_builder.build(alloc, &self.light_tree, self.*, threads);

        self.has_volumes = self.volumes.items.len > 0;

        var caustic_aabb = math.aabb.empty;

        for (self.finite_props.items) |i| {
            if (self.propHasCausticMaterial(i)) {
                caustic_aabb.mergeAssign(self.prop_aabbs.items[i]);
            }
        }

        self.caustic_aabb = caustic_aabb;
    }

    pub fn intersect(self: Scene, ray: *Ray, worker: *Worker, ipo: Interpolation, isec: *Intersection) bool {
        return self.prop_bvh.intersect(ray, worker, ipo, isec);
    }

    pub fn intersectShadow(self: Scene, ray: *Ray, worker: *Worker, isec: *Intersection) bool {
        return self.prop_bvh.intersectShadow(ray, worker, isec);
    }

    pub fn intersectVolume(self: Scene, ray: *Ray, worker: *Worker, isec: *Intersection) bool {
        return self.volume_bvh.intersect(ray, worker, .NoTangentSpace, isec);
    }

    pub fn intersectP(self: Scene, ray: Ray, worker: *Worker) bool {
        return self.prop_bvh.intersectP(ray, worker);
    }

    pub fn visibility(self: Scene, ray: Ray, filter: ?Filter, worker: *Worker) ?Vec4f {
        if (self.tinted_shadow) {
            return self.prop_bvh.visibility(ray, filter, worker);
        }

        if (self.prop_bvh.intersectP(ray, worker)) {
            return null;
        }

        return @splat(4, @as(f32, 1.0));
    }

    pub fn commitMaterials(self: *Scene, alloc: Allocator, threads: *Threads) !void {
        for (self.materials.items) |*m| {
            try m.commit(alloc, self.*, threads);
        }
    }

    pub fn calculateNumInterpolationFrames(self: *Scene, frame_step: u64, frame_duration: u64) void {
        self.num_interpolation_frames = countFrames(frame_step, frame_duration) + 1;
    }

    pub fn createEntity(self: *Scene, alloc: Allocator) !u32 {
        const p = try self.allocateProp(alloc);

        self.props.items[p].configure(@enumToInt(ShapeID.Null), &.{}, self.*);

        return p;
    }

    pub fn createProp(self: *Scene, alloc: Allocator, shape_id: u32, materials: []const u32) !u32 {
        const p = self.allocateProp(alloc) catch return Null;

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
                try self.light_ids.append(alloc, Null);
            }
        }

        if (shape_inst.finite()) {
            try self.finite_props.append(alloc, p);
        } else {
            try self.infinite_props.append(alloc, p);
        }

        // Shape has no surface
        if (1 == num_parts and 1.0 == self.material(materials[0]).ior()) {
            if (shape_inst.finite()) {
                try self.volumes.append(alloc, p);
            }
        }

        return p;
    }

    pub fn createLight(self: *Scene, alloc: Allocator, entity: u32) !void {
        const shape_inst = self.propShape(entity);

        var i: u32 = 0;
        const len = shape_inst.numParts();
        while (i < len) : (i += 1) {
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

        if (Null == f) {
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

    pub fn propAllocateFrames(self: *Scene, alloc: Allocator, entity: u32) !void {
        self.prop_frames.items[entity] = @intCast(u32, self.keyframes.items.len);

        const num_world_frames = self.num_interpolation_frames;
        const num_local_frames = num_world_frames;
        const num_frames = num_world_frames + num_local_frames;

        var i: u32 = 0;
        while (i < num_frames) : (i += 1) {
            try self.keyframes.append(alloc, .{});
        }

        self.props.items[entity].configureAnimated(self.*);
    }

    pub fn propHasAnimatedFrames(self: Scene, entity: u32) bool {
        return Null != self.prop_frames.items[entity];
    }

    pub fn propSetFrames(self: *Scene, entity: u32, frames: [*]const math.Transformation) void {
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
        alloc: Allocator,
        entity: u32,
        part: u32,
        light_id: usize,
        time: u64,
        volume: bool,
        worker: Worker,
        threads: *Threads,
    ) void {
        var shape_inst = self.propShapePtr(entity);

        const p = self.prop_parts.items[entity] + part;

        self.light_ids.items[p] = if (volume) Light.Volume_mask | @intCast(u32, light_id) else @intCast(u32, light_id);

        const m = self.material_ids.items[p];

        const variant = shape_inst.prepareSampling(alloc, part, m, &self.light_tree_builder, worker, threads) catch 0;
        self.lights.items[light_id].variant = @intCast(u16, variant);

        const trafo = self.propTransformationAt(entity, time);
        const scale = trafo.scale();

        const extent = if (volume) shape_inst.volume(part, scale) else shape_inst.area(part, scale);

        self.lights.items[light_id].extent = extent;

        const mat = &self.materials.items[m];
        const average_radiance = mat.prepareSampling(alloc, shape_inst.*, part, trafo, extent, self.*, threads);

        const f = self.prop_frames.items[entity];
        const part_aabb = shape_inst.partAabb(part, variant);

        if (Null == f) {
            var bb = part_aabb.transform(trafo.objectToWorld());
            bb.cacheRadius();

            self.light_aabbs.items[light_id] = bb;

            const cone = shape_inst.cone(part);
            const tc = trafo.objectToWorldNormal(cone);
            self.light_cones.items[light_id] = Vec4f{ tc[0], tc[1], tc[2], cone[3] };
        } else {}

        self.light_aabbs.items[light_id].bounds[1][3] = math.maxComponent3(
            self.lights.items[light_id].power(average_radiance, self.aabb(), self.*),
        );
    }

    pub fn propAabbIntersect(self: Scene, entity: usize, ray: Ray) bool {
        return self.prop_aabbs.items[entity].intersect(ray.ray);
    }

    pub fn propShape(self: Scene, entity: usize) Shape {
        return self.shapes.items[self.props.items[entity].shape];
    }

    pub fn propShapePtr(self: Scene, entity: usize) *Shape {
        return &self.shapes.items[self.props.items[entity].shape];
    }

    pub fn propMaterial(self: Scene, entity: usize, part: u32) Material {
        const p = self.prop_parts.items[entity] + part;
        return self.materials.items[self.material_ids.items[p]];
    }

    pub fn propMaterialPtr(self: Scene, entity: usize, part: u32) *Material {
        const p = self.prop_parts.items[entity] + part;
        return &self.materials.items[self.material_ids.items[p]];
    }

    pub fn propLightId(self: Scene, entity: u32, part: u32) u32 {
        const p = self.prop_parts.items[entity] + part;
        return self.light_ids.items[p];
    }

    pub fn image(self: Scene, image_id: u32) Image {
        return self.images.items[image_id];
    }

    pub fn imagePtr(self: Scene, image_id: u32) *Image {
        return &self.images.items[image_id];
    }

    pub fn material(self: Scene, material_id: u32) Material {
        return self.materials.items[material_id];
    }

    pub fn materialPtr(self: Scene, material_id: u32) *Material {
        return &self.materials.items[material_id];
    }

    pub fn shape(self: Scene, shape_id: u32) Shape {
        return self.shapes.items[shape_id];
    }

    pub fn prop(self: Scene, index: u32) Prop {
        return self.props.items[index];
    }

    pub fn numLights(self: Scene) u32 {
        return @intCast(u32, self.lights.items.len);
    }

    pub fn light(self: Scene, id: u32) Light {
        return self.lights.items[id];
    }

    pub fn randomLight(self: Scene, random: f32) LightPick {
        return self.light_distribution.sampleDiscrete(random);
    }

    pub fn randomLightSpatial(
        self: Scene,
        p: Vec4f,
        n: Vec4f,
        total_sphere: bool,
        random: f32,
        split: bool,
        buffer: *Worker.Lights,
    ) []LightPick {
        // _ = p;
        // _ = n;
        // _ = total_sphere;
        // _ = split;

        // buffer[0] = self.light_distribution.sampleDiscrete(random);
        // return buffer[0..1];

        return self.light_tree.randomLight(p, n, total_sphere, random, split, self, buffer);
    }

    pub fn lightPdfSpatial(self: Scene, id: u32, p: Vec4f, n: Vec4f, total_sphere: bool, split: bool) LightPick {
        // _ = p;
        // _ = n;
        // _ = total_sphere;
        // _ = split;

        // const pdf = self.light_distribution.pdfI(id);
        // return .{ .offset = id, .pdf = pdf };

        const light_id = Light.stripMask(id);

        const pdf = self.light_tree.pdf(p, n, total_sphere, split, light_id, self);
        return .{ .offset = light_id, .pdf = pdf };
    }

    pub fn lightArea(self: Scene, entity: u32, part: u32) f32 {
        const p = self.prop_parts.items[entity] + part;
        const light_id = self.light_ids.items[p];

        if (Null == light_id) {
            return 1.0;
        }

        return self.lights.items[light_id].extent;
    }

    pub fn lightTwoSided(self: Scene, variant: u32, light_id: usize) bool {
        _ = variant;
        return self.lights.items[light_id].two_sided;
    }

    pub fn lightPower(self: Scene, variant: u32, light_id: usize) f32 {
        _ = variant;
        return self.light_aabbs.items[light_id].bounds[1][3];
    }

    pub fn lightAabb(self: Scene, light_id: usize) AABB {
        return self.light_aabbs.items[light_id];
    }

    pub fn lightCone(self: Scene, light_id: usize) Vec4f {
        return self.light_cones.items[light_id];
    }

    fn allocateProp(self: *Scene, alloc: Allocator) !u32 {
        try self.props.append(alloc, .{});
        try self.prop_world_transformations.append(alloc, .{});
        try self.prop_world_positions.append(alloc, .{});
        try self.prop_parts.append(alloc, 0);
        try self.prop_frames.append(alloc, Null);
        try self.prop_aabbs.append(alloc, .{});

        return @intCast(u32, self.props.items.len - 1);
    }

    fn allocateLight(
        self: *Scene,
        alloc: Allocator,
        typef: Light.Type,
        two_sided: bool,
        entity: u32,
        part: u32,
    ) !void {
        try self.lights.append(alloc, .{ .typef = typef, .two_sided = two_sided, .prop = entity, .part = part });
        try self.light_aabbs.append(alloc, AABB.init(@splat(4, @as(f32, 0.0)), @splat(4, @as(f32, 0.0))));
        try self.light_cones.append(alloc, .{ 0.0, 0.0, 0.0, -1.0 });
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

            if (self.materials.items[m].emissive()) {
                return false;
            }
        }

        return true;
    }

    fn propHasCausticMaterial(self: Scene, entity: usize) bool {
        const shape_inst = self.propShape(entity);

        var i: u32 = 0;
        const len = shape_inst.numParts();
        while (i < len) : (i += 1) {
            if (!self.propMaterial(entity, i).caustic()) {
                return true;
            }
        }

        return false;
    }

    pub fn createSky(self: *Scene, alloc: Allocator) !*Sky {
        if (null == self.sky) {
            const dummy = try self.createEntity(alloc);

            self.sky = Sky{ .prop = dummy };
        }

        return &self.sky.?;
    }

    pub fn createImage(self: *Scene, alloc: Allocator, item: Image) !u32 {
        try self.images.append(alloc, item);
        return @intCast(u32, self.images.items.len - 1);
    }

    pub fn createMaterial(self: *Scene, alloc: Allocator, item: Material) !u32 {
        try self.materials.append(alloc, item);
        return @intCast(u32, self.materials.items.len - 1);
    }

    fn propCalculateWorldTransformation(self: *Scene, entity: usize, camera_pos: Vec4f) void {
        const f = self.prop_frames.items[entity];

        const shape_aabb = self.propShape(entity).aabb();

        if (Null == f) {
            var trafo = &self.prop_world_transformations.items[entity];

            trafo.setPosition(self.prop_world_positions.items[entity] - camera_pos);

            self.prop_aabbs.items[entity] = shape_aabb.transform(trafo.objectToWorld());
        } else if (Null != f) {
            const frames = self.keyframes.items.ptr + f;

            {
                var i: u32 = 0;
                const len = self.num_interpolation_frames;
                while (i < len) : (i += 1) {
                    frames[i].set(frames[len + i], camera_pos);
                }
            }

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
        }
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
