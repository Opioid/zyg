const prp = @import("prop/prop.zig");
const Prop = prp.Prop;
const Light = @import("light/light.zig").Light;
const Intersection = @import("prop/intersection.zig").Intersection;
const Material = @import("material/material.zig").Material;
const shp = @import("shape/shape.zig");
const Shape = shp.Shape;
const Ray = @import("ray.zig").Ray;
const Worker = @import("worker.zig").Worker;
const Transformation = @import("composed_transformation.zig").Composed_transformation;

const base = @import("base");
usingnamespace base;

const AABB = base.math.AABB;
const Vec4f = base.math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;
const ALU = std.ArrayListUnmanaged;

const Num_reserved_props = 32;

pub const Scene = struct {
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

    pub fn init(
        alloc: *Allocator,
        materials: *ALU(Material),
        shapes: *ALU(Shape),
        null_shape: u32,
    ) !Scene {
        return Scene{
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
        for (self.props.items) |_, i| {
            self.propCalculateWorldTransformation(i, camera_pos);
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

    pub fn createLight(self: *Scene, alloc: *Allocator, prop: u32) !void {
        const shape_inst = self.propShape(prop);

        var i: u32 = 0;
        const len = shape_inst.numParts();
        while (i < len) : (i += 1) {
            const material = self.propMaterial(prop, i);
            if (material.isEmissive()) {
                try self.allocateLight(alloc, prop, i);
            }
        }
    }

    pub fn propWorldPosition(self: Scene, entity: u32) Vec4f {
        return self.prop_world_positions.items[entity];
    }

    pub fn propTransformationAt(self: Scene, prop: usize) Transformation {
        return self.prop_world_transformations.items[prop];
    }

    pub fn propSetWorldTransformation(self: *Scene, prop: u32, t: math.Transformation) void {
        self.prop_world_transformations.items[prop].prepare(t);
        self.prop_world_positions.items[prop] = t.position;
    }

    pub fn propPrepareSampling(self: *Scene, prop: u32, part: u32, light_id: usize) void {
        const shape_inst = self.propShape(prop);

        const trafo = self.propTransformationAt(prop);
        const scale = trafo.scale();

        const extent = shape_inst.area(part, scale);

        self.lights.items[light_id].extent = extent;
    }

    pub fn propAabbIntersectP(self: Scene, prop: usize, ray: Ray) bool {
        return self.prop_aabbs.items[prop].intersectP(ray.ray);
    }

    pub fn propMaterial(self: Scene, prop: usize, part: u32) Material {
        const p = self.prop_parts.items[prop] + part;
        return self.materials.items[self.material_ids.items[p]];
    }

    pub fn propShape(self: Scene, prop: usize) Shape {
        return self.shapes.items[self.props.items[prop].shape];
    }

    pub fn shape(self: Scene, shape_id: u32) Shape {
        return self.shapes.items[shape_id];
    }

    pub fn lightArea(self: Scene, prop: u32, part: u32) f32 {
        const p = self.prop_parts.items[prop] + part;
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

    fn allocateLight(self: *Scene, alloc: *Allocator, prop: u32, part: u32) !void {
        try self.lights.append(alloc, .{ .prop = prop, .part = part });
    }

    fn propCalculateWorldTransformation(self: *Scene, entity: usize, camera_pos: Vec4f) void {
        const shape_aabb = self.propShape(entity).aabb();

        var trafo = &self.prop_world_transformations.items[entity];

        trafo.setPosition(self.prop_world_positions.items[entity].sub3(camera_pos));

        self.prop_aabbs.items[entity] = shape_aabb.transform(trafo.objectToWorld());
    }
};
