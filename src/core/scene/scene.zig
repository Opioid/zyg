const prp = @import("prop/prop.zig");
const Prop = prp.Prop;
const Light = @import("light/light.zig").Light;
const Image = @import("../image/image.zig").Image;
const Intersection = @import("prop/intersection.zig").Intersection;
const Material = @import("material/material.zig").Material;
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

const std = @import("std");
const Allocator = std.mem.Allocator;
const ALU = std.ArrayListUnmanaged;

const Num_reserved_props = 32;

const LightPick = Distribution1D.Discrete;

pub const Scene = struct {
    images: *ALU(Image),
    materials: *ALU(Material),
    shapes: *ALU(Shape),

    null_shape: u32,

    props: ALU(Prop),
    prop_world_transformations: ALU(Transformation),
    prop_world_positions: ALU(Vec4f),
    prop_parts: ALU(u32),
    prop_aabbs: ALU(AABB),

    lights: ALU(Light),

    material_ids: ALU(u32),
    light_ids: ALU(u32),

    has_tinted_shadow: bool = undefined,

    pub fn init(
        alloc: *Allocator,
        images: *ALU(Image),
        materials: *ALU(Material),
        shapes: *ALU(Shape),
        null_shape: u32,
    ) !Scene {
        return Scene{
            .images = images,
            .materials = materials,
            .shapes = shapes,
            .null_shape = null_shape,
            .props = try ALU(Prop).initCapacity(alloc, Num_reserved_props),
            .prop_world_transformations = try ALU(Transformation).initCapacity(alloc, Num_reserved_props),
            .prop_world_positions = try ALU(Vec4f).initCapacity(alloc, Num_reserved_props),
            .prop_parts = try ALU(u32).initCapacity(alloc, Num_reserved_props),
            .prop_aabbs = try ALU(AABB).initCapacity(alloc, Num_reserved_props),
            .lights = try ALU(Light).initCapacity(alloc, Num_reserved_props),
            .material_ids = try ALU(u32).initCapacity(alloc, Num_reserved_props),
            .light_ids = try ALU(u32).initCapacity(alloc, Num_reserved_props),
        };
    }

    pub fn deinit(self: *Scene, alloc: *Allocator) void {
        self.light_ids.deinit(alloc);
        self.material_ids.deinit(alloc);
        self.lights.deinit(alloc);
        self.prop_aabbs.deinit(alloc);
        self.prop_parts.deinit(alloc);
        self.prop_world_positions.deinit(alloc);
        self.prop_world_transformations.deinit(alloc);
        self.props.deinit(alloc);
    }

    pub fn compile(self: *Scene, camera_pos: Vec4f) void {
        self.has_tinted_shadow = false;

        for (self.props.items) |p, i| {
            self.propCalculateWorldTransformation(i, camera_pos);

            self.has_tinted_shadow = self.has_tinted_shadow or p.hasTintedShadow();
        }

        for (self.lights.items) |l, i| {
            l.prepareSampling(i, self);
        }
    }

    pub fn intersect(self: Scene, ray: *Ray, worker: *Worker, isec: *Intersection) bool {
        worker.node_stack.clear();

        var hit: bool = false;
        var prop: usize = prp.Null;

        for (self.props.items) |p, i| {
            if (p.intersect(i, ray, worker, &isec.geo)) {
                hit = true;
                prop = i;
            }
        }

        isec.prop = @intCast(u32, prop);
        return hit;
    }

    pub fn intersectP(self: Scene, ray: Ray, worker: *Worker) bool {
        worker.node_stack.clear();

        for (self.props.items) |p, i| {
            if (p.intersectP(i, ray, worker)) {
                return true;
            }
        }

        return false;
    }

    pub fn visibility(self: Scene, ray: Ray, filter: ?Filter, worker: *Worker) ?Vec4f {
        if (self.has_tinted_shadow) {
            worker.node_stack.clear();

            var vis = @splat(4, @as(f32, 1.0));

            for (self.props.items) |p, i| {
                const tv = p.visibility(i, ray, filter, worker) orelse return null;

                vis *= tv;
            }

            return vis;
        }

        if (self.intersectP(ray, worker)) {
            return null;
        }

        return @splat(4, @as(f32, 1.0));
    }

    pub fn createEntity(self: *Scene, alloc: *Allocator) !u32 {
        const p = try self.allocateProp(alloc);

        self.props.items[p].configure(self.null_shape, &.{}, self.*);

        return p;
    }

    pub fn createProp(self: *Scene, alloc: *Allocator, shape_id: u32, materials: []u32) !u32 {
        const p = self.allocateProp(alloc) catch return prp.Null;

        self.props.items[p].configure(shape_id, materials, self.*);

        const shape_inst = self.shape(shape_id);
        const num_parts = shape_inst.numParts();

        const parts_start = @intCast(u32, self.material_ids.items.len);
        self.prop_parts.items[p] = parts_start;

        var i: u32 = 0;
        while (i < num_parts) : (i += 1) {
            try self.material_ids.append(alloc, materials[shape_inst.partIdToMaterialId(i)]);
            try self.light_ids.append(alloc, prp.Null);
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

    pub fn propWorldPosition(self: Scene, entity: u32) Vec4f {
        return self.prop_world_positions.items[entity];
    }

    pub fn propTransformationAt(self: Scene, entity: usize) Transformation {
        return self.prop_world_transformations.items[entity];
    }

    pub fn propSetWorldTransformation(self: *Scene, entity: u32, t: math.Transformation) void {
        self.prop_world_transformations.items[entity].prepare(t);
        self.prop_world_positions.items[entity] = t.position;
    }

    pub fn propPrepareSampling(self: *Scene, entity: u32, part: u32, light_id: usize) void {
        const shape_inst = self.propShape(entity);

        const trafo = self.propTransformationAt(entity);
        const scale = trafo.scale();

        const extent = shape_inst.area(part, scale);

        self.lights.items[light_id].extent = extent;
    }

    pub fn propAabbIntersectP(self: Scene, entity: usize, ray: Ray) bool {
        return self.prop_aabbs.items[entity].intersectP(ray.ray);
    }

    pub fn propMaterial(self: Scene, entity: usize, part: u32) Material {
        const p = self.prop_parts.items[entity] + part;
        return self.materials.items[self.material_ids.items[p]];
    }

    pub fn propShape(self: Scene, entity: usize) Shape {
        return self.shapes.items[self.props.items[entity].shape];
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
        _ = self;
        _ = p;
        _ = n;
        _ = total_sphere;
        _ = random;
        _ = split;

        buffer[0].offset = 0;
        buffer[0].pdf = 1.0;

        return buffer[0..1];
    }

    pub fn lightArea(self: Scene, entity: u32, part: u32) f32 {
        const p = self.prop_parts.items[entity] + part;
        const light_id = self.light_ids.items[p];

        if (prp.Null == light_id) {
            return 1.0;
        }

        return self.lights.items[light_id].extent;
    }

    fn allocateProp(self: *Scene, alloc: *Allocator) !u32 {
        try self.props.append(alloc, .{});
        try self.prop_world_transformations.append(alloc, .{});
        try self.prop_world_positions.append(alloc, .{});
        try self.prop_parts.append(alloc, 0);
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
    }

    fn propCalculateWorldTransformation(self: *Scene, entity: usize, camera_pos: Vec4f) void {
        const shape_aabb = self.propShape(entity).aabb();

        var trafo = &self.prop_world_transformations.items[entity];

        trafo.setPosition(self.prop_world_positions.items[entity] - camera_pos);

        self.prop_aabbs.items[entity] = shape_aabb.transform(trafo.objectToWorld());
    }
};
