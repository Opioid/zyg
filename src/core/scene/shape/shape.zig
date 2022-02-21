pub const Canopy = @import("canopy.zig").Canopy;
pub const Cube = @import("cube.zig").Cube;
pub const Disk = @import("disk.zig").Disk;
pub const DistantSphere = @import("distant_sphere.zig").DistantSphere;
pub const InfiniteSphere = @import("infinite_sphere.zig").InfiniteSphere;
pub const Plane = @import("plane.zig").Plane;
pub const Rectangle = @import("rectangle.zig").Rectangle;
pub const Sphere = @import("sphere.zig").Sphere;
pub const TriangleMesh = @import("triangle/mesh.zig").Mesh;
const Ray = @import("../ray.zig").Ray;
const Worker = @import("../worker.zig").Worker;
const Scene = @import("../scene.zig").Scene;
const Filter = @import("../../image/texture/sampler.zig").Filter;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Interpolation = int.Interpolation;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const DifferentialSurface = smpl.DifferentialSurface;
const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const LightTreeBuilder = @import("../light/tree_builder.zig").Builder;
const base = @import("base");
const RNG = base.rnd.Generator;
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Shape = union(enum) {
    Null,
    Canopy: Canopy,
    Cube: Cube,
    Disk: Disk,
    DistantSphere: DistantSphere,
    InfiniteSphere: InfiniteSphere,
    Plane: Plane,
    Rectangle: Rectangle,
    Sphere: Sphere,
    TriangleMesh: TriangleMesh,

    pub fn deinit(self: *Shape, alloc: Allocator) void {
        switch (self.*) {
            .TriangleMesh => |*m| m.deinit(alloc),
            else => {},
        }
    }

    pub fn numParts(self: Shape) u32 {
        return switch (self) {
            .Null => 0,
            .TriangleMesh => |m| m.numParts(),
            else => 1,
        };
    }

    pub fn numMaterials(self: Shape) u32 {
        return switch (self) {
            .Null => 0,
            .TriangleMesh => |m| m.numMaterials(),
            else => 1,
        };
    }

    pub fn partIdToMaterialId(self: Shape, part: u32) u32 {
        return switch (self) {
            .TriangleMesh => |m| m.partMaterialId(part),
            else => part,
        };
    }

    pub fn finite(self: Shape) bool {
        return switch (self) {
            .Canopy, .DistantSphere, .InfiniteSphere, .Plane => false,
            else => true,
        };
    }

    pub fn analytical(self: Shape) bool {
        return switch (self) {
            .TriangleMesh => false,
            else => true,
        };
    }

    pub fn complex(self: Shape) bool {
        return switch (self) {
            .TriangleMesh => true,
            else => false,
        };
    }

    pub fn aabb(self: Shape) AABB {
        return switch (self) {
            .Null, .Canopy, .DistantSphere, .InfiniteSphere, .Plane => math.aabb.empty,
            .Disk, .Rectangle => AABB.init(.{ -1.0, -1.0, -0.01, 0.0 }, .{ 1.0, 1.0, 0.01, 0.0 }),
            .Cube, .Sphere => AABB.init(@splat(4, @as(f32, -1.0)), @splat(4, @as(f32, 1.0))),
            .TriangleMesh => |m| m.tree.aabb(),
        };
    }

    pub fn partAabb(self: Shape, part: u32, variant: u32) AABB {
        return switch (self) {
            .TriangleMesh => |m| m.partAabb(part, variant),
            else => self.aabb(),
        };
    }

    pub fn cone(self: Shape, part: u32) Vec4f {
        return switch (self) {
            .Disk, .Rectangle, .DistantSphere => .{ 0.0, 0.0, 1.0, 1.0 },
            .TriangleMesh => |m| m.cone(part),
            else => .{ 0.0, 0.0, 1.0, 0.0 },
        };
    }

    pub fn area(self: Shape, part: u32, scale: Vec4f) f32 {
        return switch (self) {
            .Null, .Plane => 0.0,
            .Canopy => 2.0 * std.math.pi,
            .Cube => {
                const d = @splat(4, @as(f32, 2.0)) * scale;
                return 2.0 * (d[0] * d[1] + d[0] * d[2] + d[1] * d[2]);
            },
            .Disk => std.math.pi * (scale[0] * scale[0]),

            // This calculates the solid angle, not the area!
            // I think it is what we actually need for the PDF, but results are extremely close
            .DistantSphere => (2.0 * std.math.pi) * (1.0 - (1.0 / @sqrt(scale[0] * scale[0] + 1.0))),

            .InfiniteSphere => 4.0 * std.math.pi,
            .Rectangle => 4.0 * scale[0] * scale[1],
            .Sphere => (4.0 * std.math.pi) * (scale[0] * scale[0]),
            .TriangleMesh => |m| m.area(part, scale),
        };
    }

    pub fn volume(self: Shape, part: u32, scale: Vec4f) f32 {
        _ = part;

        return switch (self) {
            .Cube => {
                const d = @splat(4, @as(f32, 2.0)) * scale;
                return d[0] * d[1] * d[2];
            },
            else => 0.0,
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
            .Canopy => Canopy.intersect(&ray.ray, trafo, isec),
            .Cube => Cube.intersect(&ray.ray, trafo, ipo, isec),
            .Disk => Disk.intersect(&ray.ray, trafo, isec),
            .DistantSphere => DistantSphere.intersect(&ray.ray, trafo, isec),
            .InfiniteSphere => InfiniteSphere.intersect(&ray.ray, trafo, isec),
            .Plane => Plane.intersect(&ray.ray, trafo, isec),
            .Rectangle => Rectangle.intersect(&ray.ray, trafo, isec),
            .Sphere => Sphere.intersect(&ray.ray, trafo, isec),
            .TriangleMesh => |m| m.intersect(&ray.ray, trafo, &worker.node_stack, ipo, isec),
        };
    }

    pub fn intersectP(self: Shape, ray: Ray, trafo: Transformation, worker: *Worker) bool {
        return switch (self) {
            .Null, .Canopy, .InfiniteSphere => false,
            .Cube => Cube.intersectP(ray.ray, trafo),
            .Disk => Disk.intersectP(ray.ray, trafo),
            .DistantSphere => DistantSphere.intersectP(ray.ray, trafo),
            .Plane => Plane.intersectP(ray.ray, trafo),
            .Rectangle => Rectangle.intersectP(ray.ray, trafo),
            .Sphere => Sphere.intersectP(ray.ray, trafo),
            .TriangleMesh => |m| m.intersectP(ray.ray, trafo, &worker.node_stack),
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
            .Null, .Canopy, .DistantSphere, .InfiniteSphere => {
                return @splat(4, @as(f32, 1.0));
            },
            .Cube => Cube.visibility(ray.ray, trafo, entity, filter, worker.scene.*),
            .Disk => Disk.visibility(ray.ray, trafo, entity, filter, worker.scene.*),
            .Plane => Plane.visibility(ray.ray, trafo, entity, filter, worker.scene.*),
            .Rectangle => Rectangle.visibility(ray.ray, trafo, entity, filter, worker.scene.*),
            .Sphere => Sphere.visibility(ray.ray, trafo, entity, filter, worker.scene.*),
            .TriangleMesh => |m| m.visibility(ray.ray, trafo, entity, filter, worker),
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
    ) ?SampleTo {
        return switch (self) {
            .Canopy => Canopy.sampleTo(trafo, sampler, rng),
            .Disk => Disk.sampleTo(p, trafo, extent, two_sided, sampler, rng),
            .DistantSphere => DistantSphere.sampleTo(trafo, extent, sampler, rng),
            .InfiniteSphere => InfiniteSphere.sampleTo(n, trafo, total_sphere, sampler, rng),
            .Rectangle => Rectangle.sampleTo(p, trafo, extent, two_sided, sampler, rng),
            .Sphere => Sphere.sampleTo(p, trafo, sampler, rng),
            .TriangleMesh => |m| m.sampleTo(
                part,
                variant,
                p,
                n,
                trafo,
                extent,
                two_sided,
                total_sphere,
                sampler,
                rng,
            ),
            else => null,
        };
    }

    pub fn sampleVolumeTo(
        self: Shape,
        part: u32,
        p: Vec4f,
        trafo: Transformation,
        extent: f32,
        sampler: *Sampler,
        rng: *RNG,
    ) ?SampleTo {
        _ = part;

        return switch (self) {
            .Cube => Cube.sampleVolumeTo(p, trafo, extent, sampler, rng),
            else => null,
        };
    }

    pub fn sampleFrom(
        self: Shape,
        part: u32,
        variant: u32,
        trafo: Transformation,
        extent: f32,
        two_sided: bool,
        sampler: *Sampler,
        rng: *RNG,
        importance_uv: Vec2f,
        bounds: AABB,
    ) ?SampleFrom {
        return switch (self) {
            .Disk => Disk.sampleFrom(trafo, extent, two_sided, sampler, rng, importance_uv),
            .DistantSphere => DistantSphere.sampleFrom(trafo, extent, sampler, rng, importance_uv, bounds),
            .Rectangle => Rectangle.sampleFrom(trafo, extent, two_sided, sampler, rng, importance_uv),
            .Sphere => Sphere.sampleFrom(trafo, extent, sampler, rng, importance_uv),
            .TriangleMesh => |m| m.sampleFrom(
                part,
                variant,
                trafo,
                extent,
                two_sided,
                sampler,
                rng,
                importance_uv,
            ),
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
            .Canopy => Canopy.sampleToUv(uv, trafo),
            .InfiniteSphere => InfiniteSphere.sampleToUv(uv, trafo),
            .Rectangle => Rectangle.sampleToUv(p, uv, trafo, extent, two_sided),
            else => null,
        };
    }

    pub fn sampleVolumeToUvw(
        self: Shape,
        part: u32,
        p: Vec4f,
        uvw: Vec4f,
        trafo: Transformation,
        extent: f32,
    ) ?SampleTo {
        _ = part;

        return switch (self) {
            .Cube => Cube.sampleVolumeToUvw(p, uvw, trafo, extent),
            else => null,
        };
    }

    pub fn sampleFromUv(
        self: Shape,
        part: u32,
        uv: Vec2f,
        trafo: Transformation,
        extent: f32,
        two_sided: bool,
        sampler: *Sampler,
        rng: *RNG,
        importance_uv: Vec2f,
        bounds: AABB,
    ) ?SampleFrom {
        _ = part;

        return switch (self) {
            .Canopy => Canopy.sampleFromUv(uv, trafo, importance_uv, bounds),
            .Rectangle => Rectangle.sampleFromUv(uv, trafo, extent, two_sided, sampler, rng, importance_uv),
            else => null,
        };
    }

    pub fn sampleVolumeFromUvw(
        self: Shape,
        part: u32,
        uvw: Vec4f,
        trafo: Transformation,
        extent: f32,
        importance_uv: Vec2f,
    ) ?SampleFrom {
        _ = part;

        return switch (self) {
            .Cube => Cube.sampleVolumeFromUvw(uvw, trafo, extent, importance_uv),
            else => null,
        };
    }

    pub fn pdf(
        self: Shape,
        variant: u32,
        ray: Ray,
        n: Vec4f,
        isec: Intersection,
        trafo: Transformation,
        extent: f32,
        two_sided: bool,
        total_sphere: bool,
    ) f32 {
        return switch (self) {
            .Cube, .Null, .Plane => 0.0,
            .Canopy => 1.0 / (2.0 * std.math.pi),
            .Disk => Rectangle.pdf(ray.ray, trafo, extent, two_sided),
            .DistantSphere => 1.0 / extent,
            .InfiniteSphere => InfiniteSphere.pdf(total_sphere),
            .Rectangle => Rectangle.pdf(ray.ray, trafo, extent, two_sided),
            .Sphere => Sphere.pdf(ray.ray, trafo),
            .TriangleMesh => |m| m.pdf(variant, ray.ray, n, isec, trafo, extent, two_sided, total_sphere),
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
            .Canopy => 1.0 / (2.0 * std.math.pi),
            .InfiniteSphere => InfiniteSphere.pdfUv(isec),
            .Rectangle => Rectangle.pdf(ray.ray, trafo, extent, two_sided),
            .Sphere => Sphere.pdfUv(ray.ray, isec, extent),
            else => 0.0,
        };
    }

    pub fn volumePdf(
        self: Shape,
        ray: Ray,
        isec: Intersection,
        trafo: Transformation,
        extent: f32,
    ) f32 {
        _ = isec;
        _ = trafo;

        return switch (self) {
            .Cube => Cube.volumePdf(ray.ray, extent),
            else => 0.0,
        };
    }

    pub fn uvWeight(self: Shape, uv: Vec2f) f32 {
        return switch (self) {
            .Canopy => Canopy.uvWeight(uv),
            .InfiniteSphere => @sin(uv[1] * std.math.pi),
            else => 1.0,
        };
    }

    pub fn prepareSampling(
        self: *Shape,
        alloc: Allocator,
        part: u32,
        material: u32,
        builder: *LightTreeBuilder,
        scene: Scene,
        threads: *Threads,
    ) !u32 {
        return switch (self.*) {
            .TriangleMesh => |*m| try m.prepareSampling(alloc, part, material, builder, scene, threads),
            else => 0,
        };
    }

    pub fn differentialSurface(self: Shape, primitive: u32) DifferentialSurface {
        return switch (self) {
            .TriangleMesh => |m| m.differentialSurface(primitive),
            else => .{ .dpdu = .{ 1.0, 0.0, 0.0, 0.0 }, .dpdv = .{ 0.0, -1.0, 0.0, 0.0 } },
        };
    }
};
