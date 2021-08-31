const prop = @import("prop/prop.zig");
const Prop = prop.Prop;
const Intersection = @import("prop/intersection.zig").Intersection;
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

const Num_reserved_props = 32;

pub const Scene = struct {
    shapes: *std.ArrayListUnmanaged(Shape),

    null_shape: u32,

    props: std.ArrayListUnmanaged(Prop),
    prop_world_transformations: std.ArrayListUnmanaged(Transformation),
    prop_world_positions: std.ArrayListUnmanaged(Vec4f),
    prop_aabbs: std.ArrayListUnmanaged(AABB),

    pub fn init(alloc: *Allocator, shapes: *std.ArrayListUnmanaged(Shape), null_shape: u32) !Scene {
        return Scene{
            .props = try std.ArrayListUnmanaged(Prop).initCapacity(alloc, Num_reserved_props),
            .prop_world_transformations = try std.ArrayListUnmanaged(Transformation).initCapacity(alloc, Num_reserved_props),
            .prop_world_positions = try std.ArrayListUnmanaged(Vec4f).initCapacity(alloc, Num_reserved_props),
            .prop_aabbs = try std.ArrayListUnmanaged(AABB).initCapacity(alloc, Num_reserved_props),
            .shapes = shapes,
            .null_shape = null_shape,
        };
    }

    pub fn deinit(self: *Scene, alloc: *Allocator) void {
        self.prop_aabbs.deinit(alloc);
        self.prop_world_positions.deinit(alloc);
        self.prop_world_transformations.deinit(alloc);
        self.props.deinit(alloc);
    }

    pub fn compile(self: *Scene, camera_pos: Vec4f) void {
        for (self.props.items) |_, i| {
            self.propCalculateWorldTransformation(i, camera_pos);
        }
    }

    pub fn intersect(self: Scene, ray: *Ray, worker: *Worker, isec: *Intersection) bool {
        worker.node_stack.clear();

        var hit: bool = false;

        for (self.props.items) |p, i| {
            if (p.intersect(i, ray, worker, &isec.geo)) {
                hit = true;
            }
        }

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

    pub fn createEntity(self: *Scene, alloc: *Allocator) u32 {
        const p = self.allocateProp(alloc) catch return prop.Null;

        self.props.items[p].configure(self.null_shape, self.*);

        return p;
    }

    pub fn createProp(self: *Scene, alloc: *Allocator, shape_id: u32) u32 {
        const p = self.allocateProp(alloc) catch return prop.Null;

        self.props.items[p].configure(shape_id, self.*);

        return p;
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

    pub fn propAabbIntersectP(self: Scene, entity: usize, ray: Ray) bool {
        return self.prop_aabbs.items[entity].intersectP(ray.ray);
    }

    pub fn propShape(self: Scene, entity: usize) Shape {
        return self.shapes.items[self.props.items[entity].shape];
    }

    pub fn shape(self: Scene, shape_id: u32) Shape {
        return self.shapes.items[shape_id];
    }

    fn allocateProp(self: *Scene, alloc: *Allocator) !u32 {
        try self.props.append(alloc, .{});
        try self.prop_world_transformations.append(alloc, .{});
        try self.prop_world_positions.append(alloc, .{});
        try self.prop_aabbs.append(alloc, .{});

        return @intCast(u32, self.props.items.len - 1);
    }

    fn propCalculateWorldTransformation(self: *Scene, entity: usize, camera_pos: Vec4f) void {
        const shape_aabb = self.propShape(entity).aabb();

        var trafo = &self.prop_world_transformations.items[entity];

        trafo.setPosition(self.prop_world_positions.items[entity].sub3(camera_pos));

        self.prop_aabbs.items[entity] = shape_aabb.transform(trafo.objectToWorld());
    }
};
