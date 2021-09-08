pub const Plane = @import("plane.zig").Plane;
pub const Rectangle = @import("rectangle.zig").Rectangle;
pub const Sphere = @import("sphere.zig").Sphere;
pub const Triangle_mesh = @import("triangle/mesh.zig").Mesh;
const Ray = @import("../ray.zig").Ray;
const Worker = @import("../worker.zig").Worker;
const Intersection = @import("intersection.zig").Intersection;
const Transformation = @import("../composed_transformation.zig").Composed_transformation;

const base = @import("base");
usingnamespace base;

const AABB = math.AABB;
const Vec4f = base.math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Shape = union(enum) {
    Null,
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

    pub fn isComplex(self: Shape) bool {
        return switch (self) {
            .Triangle_mesh => true,
            else => false,
        };
    }

    pub fn aabb(self: Shape) AABB {
        return switch (self) {
            .Null, .Plane => math.aabb.empty,
            .Rectangle => AABB.init(Vec4f.init3(-1.0, -1.0, -0.01), Vec4f.init3(1.0, 1.0, 0.01)),
            .Sphere => AABB.init(Vec4f.init1(-1.0), Vec4f.init1(1.0)),
            .Triangle_mesh => |m| m.tree.aabb(),
        };
    }

    pub fn area(self: Shape, part: u32, scale: Vec4f) f32 {
        return switch (self) {
            .Null, .Plane => 0.0,
            .Rectangle => 4.0 * scale.v[0] * scale.v[1],
            .Sphere => (4.0 * std.math.pi) * (scale.v[0] * scale.v[0]),
            .Triangle_mesh => |m| m.area(part, scale),
        };
    }

    pub fn intersect(self: Shape, ray: *Ray, trafo: Transformation, worker: *Worker, isec: *Intersection) bool {
        return switch (self) {
            .Null => false,
            .Plane => Plane.intersect(&ray.ray, trafo, isec),
            .Rectangle => Rectangle.intersect(&ray.ray, trafo, isec),
            .Sphere => Sphere.intersect(&ray.ray, trafo, isec),
            .Triangle_mesh => |m| m.intersect(&ray.ray, trafo, &worker.node_stack, isec),
        };
    }

    pub fn intersectP(self: Shape, ray: Ray, trafo: Transformation, worker: *Worker) bool {
        return switch (self) {
            .Null => false,
            .Plane => Plane.intersectP(ray.ray, trafo),
            .Rectangle => Rectangle.intersectP(ray.ray, trafo),
            .Sphere => Sphere.intersectP(ray.ray, trafo),
            .Triangle_mesh => |m| m.intersectP(ray.ray, trafo, &worker.node_stack),
        };
    }
};
