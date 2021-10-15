pub const Disk = @import("disk.zig").Disk;
pub const InfiniteSphere = @import("infinite_sphere.zig").InfiniteSphere;
pub const Plane = @import("plane.zig").Plane;
pub const Rectangle = @import("rectangle.zig").Rectangle;
pub const Sphere = @import("sphere.zig").Sphere;
pub const Triangle_mesh = @import("triangle/mesh.zig").Mesh;
const Ray = @import("../ray.zig").Ray;
const Worker = @import("../worker.zig").Worker;
const Filter = @import("../../image/texture/sampler.zig").Filter;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Interpolation = int.Interpolation;
const SampleTo = @import("sample.zig").To;
const Transformation = @import("../composed_transformation.zig").ComposedTransformation;

const base = @import("base");
const RNG = base.rnd.Generator;
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Shape = union(enum) {
    Null,
    Disk: Disk,
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
            .Null => 0,
            .Triangle_mesh => |m| m.numParts(),
            else => 1,
        };
    }

    pub fn numMaterials(self: Shape) u32 {
        return switch (self) {
            .Null => 0,
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

    pub fn isAnalytical(self: Shape) bool {
        return switch (self) {
            .Triangle_mesh => false,
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
            .Disk, .Rectangle => AABB.init(.{ -1.0, -1.0, -0.01, 0.0 }, .{ 1.0, 1.0, 0.01, 0.0 }),
            .Sphere => AABB.init(@splat(4, @as(f32, -1.0)), @splat(4, @as(f32, 1.0))),
            .Triangle_mesh => |m| m.tree.aabb(),
        };
    }

    pub fn area(self: Shape, part: u32, scale: Vec4f) f32 {
        return switch (self) {
            .Null, .Plane => 0.0,
            .Disk => std.math.pi * (scale[0] * scale[0]),
            .InfiniteSphere => 4.0 * std.math.pi,
            .Rectangle => 4.0 * scale[0] * scale[1],
            .Sphere => (4.0 * std.math.pi) * (scale[0] * scale[0]),
            .Triangle_mesh => |m| m.area(part, scale),
        };
    }

    pub fn intersect(
        self: Shape,
        ray: *Ray,
        trafo: Transformation,
        worker: *Worker,
        ipo: Interpolation,
        isec: *Intersection,
    ) bool {
        return switch (self) {
            .Null => false,
            .Disk => Disk.intersect(&ray.ray, trafo, isec),
            .InfiniteSphere => InfiniteSphere.intersect(&ray.ray, trafo, isec),
            .Plane => Plane.intersect(&ray.ray, trafo, isec),
            .Rectangle => Rectangle.intersect(&ray.ray, trafo, isec),
            .Sphere => Sphere.intersect(&ray.ray, trafo, isec),
            .Triangle_mesh => |m| m.intersect(&ray.ray, trafo, &worker.node_stack, ipo, isec),
        };
    }

    pub fn intersectP(self: Shape, ray: Ray, trafo: Transformation, worker: *Worker) bool {
        return switch (self) {
            .Null, .InfiniteSphere => false,
            .Disk => Disk.intersectP(ray.ray, trafo),
            .Plane => Plane.intersectP(ray.ray, trafo),
            .Rectangle => Rectangle.intersectP(ray.ray, trafo),
            .Sphere => Sphere.intersectP(ray.ray, trafo),
            .Triangle_mesh => |m| m.intersectP(ray.ray, trafo, &worker.node_stack),
        };
    }

    pub fn visibility(
        self: Shape,
        ray: Ray,
        trafo: Transformation,
        entity: usize,
        filter: ?Filter,
        worker: *Worker,
    ) ?Vec4f {
        return switch (self) {
            .Null, .InfiniteSphere => {
                return @splat(4, @as(f32, 1.0));
            },
            .Disk => Disk.visibility(ray.ray, trafo, entity, filter, worker.*),
            .Plane => Plane.visibility(ray.ray, trafo, entity, filter, worker.*),
            .Rectangle => Rectangle.visibility(ray.ray, trafo, entity, filter, worker.*),
            .Sphere => Sphere.visibility(ray.ray, trafo, entity, filter, worker.*),
            .Triangle_mesh => |m| m.visibility(ray.ray, trafo, entity, filter, worker),
        };
    }

    pub fn sampleTo(
        self: Shape,
        part: u32,
        variant: u32,
        p: Vec4f,
        n: Vec4f,
        trafo: Transformation,
        extent: f32,
        two_sided: bool,
        total_sphere: bool,
        sampler: *Sampler,
        rng: *RNG,
        sampler_d: usize,
    ) ?SampleTo {
        _ = part;
        _ = variant;

        return switch (self) {
            .Disk => Disk.sampleTo(p, trafo, extent, two_sided, sampler, rng, sampler_d),
            .InfiniteSphere => InfiniteSphere.sampleTo(n, trafo, total_sphere, sampler, rng, sampler_d),
            .Rectangle => Rectangle.sampleTo(p, trafo, extent, two_sided, sampler, rng, sampler_d),
            .Sphere => Sphere.sampleTo(p, trafo, sampler, rng, sampler_d),
            else => null,
        };
    }

    pub fn sampleToUv(
        self: Shape,
        part: u32,
        p: Vec4f,
        uv: Vec2f,
        trafo: Transformation,
        extent: f32,
        two_sided: bool,
    ) ?SampleTo {
        _ = part;

        return switch (self) {
            .InfiniteSphere => InfiniteSphere.sampleToUv(uv, trafo),
            .Rectangle => Rectangle.sampleToUv(p, uv, trafo, extent, two_sided),
            else => null,
        };
    }

    pub fn pdf(
        self: Shape,
        variant: u32,
        ray: Ray,
        p: Vec4f,
        isec: Intersection,
        trafo: Transformation,
        extent: f32,
        two_sided: bool,
        total_sphere: bool,
    ) f32 {
        _ = variant;
        _ = p;
        _ = isec;

        return switch (self) {
            .Disk => Rectangle.pdf(ray.ray, trafo, extent, two_sided),
            .InfiniteSphere => InfiniteSphere.pdf(total_sphere),
            .Rectangle => Rectangle.pdf(ray.ray, trafo, extent, two_sided),
            .Sphere => Sphere.pdf(ray.ray, trafo),
            else => 0.0,
        };
    }

    pub fn pdfUv(
        self: Shape,
        ray: Ray,
        isec: Intersection,
        trafo: Transformation,
        extent: f32,
        two_sided: bool,
    ) f32 {
        return switch (self) {
            .InfiniteSphere => InfiniteSphere.pdfUv(isec),
            .Rectangle => Rectangle.pdf(ray.ray, trafo, extent, two_sided),
            .Sphere => Sphere.pdfUv(ray.ray, isec, extent),
            else => 0.0,
        };
    }

    pub fn uvWeight(self: Shape, uv: Vec2f) f32 {
        return switch (self) {
            .InfiniteSphere => @sin(uv[1] * std.math.pi),
            else => 1.0,
        };
    }

    pub fn prepareSampling(self: *Shape, part: u32) void {
        return switch (self.*) {
            .Triangle_mesh => |*m| m.prepareSampling(part),
            else => {},
        };
    }
};
