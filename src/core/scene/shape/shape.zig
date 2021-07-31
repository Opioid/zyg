pub const Plane = @import("plane.zig").Plane;
pub const Sphere = @import("sphere.zig").Sphere;
const Intersection = @import("intersection.zig").Intersection;

const base = @import("base");
usingnamespace base;

//const Vec4f = base.math.Vec4f;
const Ray = base.math.Ray;

const Transformation = @import("../composed_transformation.zig").Composed_transformation;

pub const Shape = union(enum) {
    Null,
    Plane: Plane,
    Sphere: Sphere,

    pub fn intersect(self: Shape, ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        return switch (self) {
            .Null => false,
            .Plane => Plane.intersect(ray, trafo, isec),
            .Sphere => Sphere.intersect(ray, trafo, isec),
        };
    }

    pub fn intersectP(self: Shape, ray: Ray, trafo: Transformation) bool {
        return switch (self) {
            .Null => false,
            .Plane => Plane.intersectP(ray, trafo),
            .Sphere => Sphere.intersectP(ray, trafo),
        };
    }
};
