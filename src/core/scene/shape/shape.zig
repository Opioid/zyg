pub const Plane = @import("plane.zig").Plane;
pub const Rectangle = @import("rectangle.zig").Rectangle;
pub const Sphere = @import("sphere.zig").Sphere;
pub const Triangle_mesh = @import("triangle/mesh.zig").Mesh;
const Intersection = @import("intersection.zig").Intersection;
const Transformation = @import("../composed_transformation.zig").Composed_transformation;

const base = @import("base");
usingnamespace base;

//const Vec4f = base.math.Vec4f;
const Ray = base.math.Ray;

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
            .Null => {},
            .Plane => {},
            .Rectangle => {},
            .Sphere => {},
            .Triangle_mesh => |*m| m.deinit(alloc),
        }
    }

    pub fn intersect(self: Shape, ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        return switch (self) {
            .Null => false,
            .Plane => Plane.intersect(ray, trafo, isec),
            .Rectangle => Rectangle.intersect(ray, trafo, isec),
            .Sphere => Sphere.intersect(ray, trafo, isec),
            .Triangle_mesh => |m| m.intersect(ray, trafo, isec),
        };
    }

    pub fn intersectP(self: Shape, ray: Ray, trafo: Transformation) bool {
        return switch (self) {
            .Null => false,
            .Plane => Plane.intersectP(ray, trafo),
            .Rectangle => Rectangle.intersectP(ray, trafo),
            .Sphere => Sphere.intersectP(ray, trafo),
            .Triangle_mesh => |m| m.intersectP(ray, trafo),
        };
    }
};
