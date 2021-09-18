pub const InfiniteSphere = @import("infinite_sphere.zig").InfiniteSphere;
pub const Plane = @import("plane.zig").Plane;
pub const Rectangle = @import("rectangle.zig").Rectangle;
pub const Sphere = @import("sphere.zig").Sphere;
pub const Triangle_mesh = @import("triangle/mesh.zig").Mesh;
const Ray = @import("../ray.zig").Ray;
const Worker = @import("../worker.zig").Worker;
const Intersection = @import("intersection.zig").Intersection;
const Transformation = @import("../composed_transformation.zig").ComposedTransformation;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Shape = union(enum) {
    Null,
    InfiniteSphere: InfiniteSphere,
    Plane: Plane,
    Rectangle: Rectangle,
    Sphere: Sphere,
    Triangle_mesh: Triangle_mesh,

    pub fn deinit(self: *Shape, alloc: *Allocator) void {
        switch (self.*) {
            .Triangle_mesh => |*m| m.deinit(alloc),
            else => {},
        }
    }

    pub fn numParts(self: Shape) u32 {
        return switch (self) {
            .Triangle_mesh => |m| m.numParts(),
            else => 1,
        };
    }

    pub fn numMaterials(self: Shape) u32 {
        return switch (self) {
            .Triangle_mesh => |m| m.numMaterials(),
            else => 1,
        };
    }

    pub fn partIdToMaterialId(self: Shape, part: u32) u32 {
        return switch (self) {
            .Triangle_mesh => |m| m.partIdToMaterialId(part),
            else => part,
        };
    }

    pub fn isFinite(self: Shape) bool {
        return switch (self) {
            .InfiniteSphere, .Plane => false,
            else => true,
        };
    }

    pub fn isComplex(self: Shape) bool {
        return switch (self) {
            .Triangle_mesh => true,
            else => false,
        };
    }

    pub fn aabb(self: Shape) AABB {
        return switch (self) {
            .Null, .InfiniteSphere, .Plane => math.aabb.empty,
            .Rectangle => AABB.init(.{ -1.0, -1.0, -0.01, 0.0 }, .{ 1.0, 1.0, 0.01, 0.0 }),
            .Sphere => AABB.init(@splat(4, @as(f32, -1.0)), @splat(4, @as(f32, 1.0))),
            .Triangle_mesh => |m| m.tree.aabb(),
        };
    }

    pub fn area(self: Shape, part: u32, scale: Vec4f) f32 {
        return switch (self) {
            .Null, .Plane => 0.0,
            .InfiniteSphere => 4.0 * std.math.pi,
            .Rectangle => 4.0 * scale[0] * scale[1],
            .Sphere => (4.0 * std.math.pi) * (scale[0] * scale[0]),
            .Triangle_mesh => |m| m.area(part, scale),
        };
    }

    pub fn intersect(self: Shape, ray: *Ray, trafo: Transformation, worker: *Worker, isec: *Intersection) bool {
        return switch (self) {
            .Null => false,
            .InfiniteSphere => InfiniteSphere.intersect(&ray.ray, trafo, isec),
            .Plane => Plane.intersect(&ray.ray, trafo, isec),
            .Rectangle => Rectangle.intersect(&ray.ray, trafo, isec),
            .Sphere => Sphere.intersect(&ray.ray, trafo, isec),
            .Triangle_mesh => |m| m.intersect(&ray.ray, trafo, &worker.node_stack, isec),
        };
    }

    pub fn intersectP(self: Shape, ray: Ray, trafo: Transformation, worker: *Worker) bool {
        return switch (self) {
            .Null, .InfiniteSphere => false,
            .Plane => Plane.intersectP(ray.ray, trafo),
            .Rectangle => Rectangle.intersectP(ray.ray, trafo),
            .Sphere => Sphere.intersectP(ray.ray, trafo),
            .Triangle_mesh => |m| m.intersectP(ray.ray, trafo, &worker.node_stack),
        };
    }

    pub fn visibility(self: Shape, ray: Ray, trafo: Transformation, entity: usize, worker: *Worker, vis: *Vec4f) bool {
        return switch (self) {
            .Null, .InfiniteSphere => {
                vis.* = @splat(4, @as(f32, 1.0));
                return true;
            },
            .Plane => Plane.visibility(ray.ray, trafo, entity, worker.*, vis),
            .Rectangle => Rectangle.visibility(ray.ray, trafo, entity, worker.*, vis),
            .Sphere => Sphere.visibility(ray.ray, trafo, entity, worker.*, vis),
            .Triangle_mesh => |m| m.visibility(ray.ray, trafo, entity, worker, vis),
        };
    }
};
