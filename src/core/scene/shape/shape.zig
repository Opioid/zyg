pub const Canopy = @import("canopy.zig").Canopy;
pub const Cube = @import("cube.zig").Cube;
pub const CurveMesh = @import("curve/curve_mesh.zig").Mesh;
pub const Disk = @import("disk.zig").Disk;
pub const DistantSphere = @import("distant_sphere.zig").DistantSphere;
pub const InfiniteSphere = @import("infinite_sphere.zig").InfiniteSphere;
pub const Plane = @import("plane.zig").Plane;
pub const Rectangle = @import("rectangle.zig").Rectangle;
pub const Sphere = @import("sphere.zig").Sphere;
pub const TriangleMesh = @import("triangle/triangle_mesh.zig").Mesh;
const ro = @import("../ray_offset.zig");
const Scene = @import("../scene.zig").Scene;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Volume = int.Volume;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const DifferentialSurface = smpl.DifferentialSurface;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const LightTreeBuilder = @import("../light/light_tree_builder.zig").Builder;
const Worker = @import("../../rendering/worker.zig").Worker;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Shape = union(enum) {
    pub const MaxSamples = 64;
    pub const SamplesTo = [MaxSamples]SampleTo;

    Canopy: Canopy,
    Cube: Cube,
    CurveMesh: CurveMesh,
    Disk: Disk,
    DistantSphere: DistantSphere,
    InfiniteSphere: InfiniteSphere,
    Plane: Plane,
    Rectangle: Rectangle,
    Sphere: Sphere,
    TriangleMesh: TriangleMesh,

    pub fn deinit(self: *Shape, alloc: Allocator) void {
        switch (self.*) {
            inline .CurveMesh, .TriangleMesh => |*m| m.deinit(alloc),
            else => {},
        }
    }

    pub fn numParts(self: *const Shape) u32 {
        return switch (self.*) {
            .TriangleMesh => |m| m.numParts(),
            else => 1,
        };
    }

    pub fn numMaterials(self: *const Shape) u32 {
        return switch (self.*) {
            .TriangleMesh => |m| m.numMaterials(),
            else => 1,
        };
    }

    pub fn partIdToMaterialId(self: *const Shape, part: u32) u32 {
        return switch (self.*) {
            .TriangleMesh => |m| m.partMaterialId(part),
            else => part,
        };
    }

    pub fn finite(self: *const Shape) bool {
        return switch (self.*) {
            .Canopy, .DistantSphere, .InfiniteSphere, .Plane => false,
            else => true,
        };
    }

    pub fn infiniteTMax(self: *const Shape) f32 {
        return switch (self.*) {
            .Canopy, .InfiniteSphere => ro.Ray_max_t,
            .DistantSphere => ro.Almost_ray_max_t,
            else => 0.0,
        };
    }

    pub fn analytical(self: *const Shape) bool {
        return switch (self.*) {
            .CurveMesh, .TriangleMesh => false,
            else => true,
        };
    }

    pub fn complex(self: *const Shape) bool {
        return switch (self.*) {
            .CurveMesh, .TriangleMesh => true,
            else => false,
        };
    }

    pub fn aabb(self: *const Shape) AABB {
        return switch (self.*) {
            .Canopy, .DistantSphere, .InfiniteSphere, .Plane => math.aabb.Empty,
            .Disk, .Rectangle => AABB.init(.{ -1.0, -1.0, -0.01, 0.0 }, .{ 1.0, 1.0, 0.01, 0.0 }),
            .Cube, .Sphere => AABB.init(@splat(-1.0), @splat(1.0)),
            inline .CurveMesh, .TriangleMesh => |*m| m.tree.aabb(),
        };
    }

    pub fn partAabb(self: *const Shape, part: u32, variant: u32) AABB {
        return switch (self.*) {
            .TriangleMesh => |*m| m.partAabb(part, variant),
            else => self.aabb(),
        };
    }

    pub fn partCone(self: *const Shape, part: u32, variant: u32) Vec4f {
        return switch (self.*) {
            .Disk, .Rectangle, .DistantSphere => .{ 0.0, 0.0, 1.0, 1.0 },
            .TriangleMesh => |*m| m.partCone(part, variant),
            else => .{ 0.0, 0.0, 1.0, -1.0 },
        };
    }

    pub fn area(self: *const Shape, part: u32, scale: Vec4f) f32 {
        return switch (self.*) {
            .Plane => 0.0,
            .Canopy => 2.0 * std.math.pi,
            .Cube => {
                const d = @as(Vec4f, @splat(2.0)) * scale;
                return 2.0 * (d[0] * d[1] + d[0] * d[2] + d[1] * d[2]);
            },
            .CurveMesh => 0.0,
            .Disk => std.math.pi * (scale[0] * scale[0]),

            // This calculates the solid angle, not the area!
            // I think it is what we actually need for the PDF, but results are extremely close
            .DistantSphere => DistantSphere.solidAngle(scale[0]),

            .InfiniteSphere => 4.0 * std.math.pi,
            .Rectangle => 4.0 * scale[0] * scale[1],
            .Sphere => (4.0 * std.math.pi) * (scale[0] * scale[0]),

            .TriangleMesh => |m| m.area(part, scale),
        };
    }

    pub fn volume(self: *const Shape, scale: Vec4f) f32 {
        return switch (self.*) {
            .Cube => {
                const d = @as(Vec4f, @splat(2.0)) * scale;
                return d[0] * d[1] * d[2];
            },
            else => 0.0,
        };
    }

    pub fn intersect(self: *const Shape, ray: Ray, trafo: Trafo) Intersection {
        return switch (self.*) {
            .Canopy => Canopy.intersect(ray, trafo),
            .Cube => Cube.intersect(ray, trafo),
            .CurveMesh => |m| m.intersect(ray, trafo),
            .Disk => Disk.intersect(ray, trafo),
            .DistantSphere => DistantSphere.intersect(ray, trafo),
            .InfiniteSphere => InfiniteSphere.intersect(ray),
            .Plane => Plane.intersect(ray, trafo),
            .Rectangle => Rectangle.intersect(ray, trafo),
            .Sphere => Sphere.intersect(ray, trafo),
            .TriangleMesh => |m| m.intersect(ray, trafo),
        };
    }

    pub fn fragment(self: *const Shape, ray: Ray, frag: *Fragment) void {
        switch (self.*) {
            .Canopy => Canopy.fragment(ray, frag),
            .Cube => Cube.fragment(ray, frag),
            .CurveMesh => |m| m.fragment(ray, frag),
            .Disk => Disk.fragment(ray, frag),
            .DistantSphere => DistantSphere.fragment(ray, frag),
            .InfiniteSphere => InfiniteSphere.fragment(ray, frag),
            .Plane => Plane.fragment(ray, frag),
            .Rectangle => Rectangle.fragment(ray, frag),
            .Sphere => Sphere.fragment(ray, frag),
            .TriangleMesh => |m| m.fragment(frag),
        }
    }

    pub fn intersectP(self: *const Shape, ray: Ray, trafo: Trafo) bool {
        return switch (self.*) {
            .Canopy, .InfiniteSphere => false,
            .Cube => Cube.intersectP(ray, trafo),
            .CurveMesh => |m| m.intersectP(ray, trafo),
            .Disk => Disk.intersectP(ray, trafo),
            .DistantSphere => DistantSphere.intersectP(ray, trafo),
            .Plane => Plane.intersectP(ray, trafo),
            .Rectangle => Rectangle.intersectP(ray, trafo),
            .Sphere => Sphere.intersectP(ray, trafo),
            .TriangleMesh => |m| m.intersectP(ray, trafo),
        };
    }

    pub fn visibility(
        self: *const Shape,
        ray: Ray,
        trafo: Trafo,
        entity: u32,
        sampler: *Sampler,
        scene: *const Scene,
        tr: *Vec4f,
    ) bool {
        return switch (self.*) {
            .Cube => Cube.visibility(ray, trafo, entity, sampler, scene, tr),
            .CurveMesh => |m| m.visibility(ray, trafo, tr),
            .Disk => Disk.visibility(ray, trafo, entity, sampler, scene, tr),
            .Plane => Plane.visibility(ray, trafo, entity, sampler, scene, tr),
            .Rectangle => Rectangle.visibility(ray, trafo, entity, sampler, scene, tr),
            .Sphere => Sphere.visibility(ray, trafo, entity, sampler, scene, tr),
            .TriangleMesh => |m| m.visibility(ray, trafo, entity, sampler, scene, tr),
            else => true,
        };
    }

    pub fn transmittance(
        self: *const Shape,
        ray: Ray,
        depth: u32,
        trafo: Trafo,
        entity: u32,
        sampler: *Sampler,
        worker: *Worker,
        tr: *Vec4f,
    ) bool {
        return switch (self.*) {
            .Cube => Cube.transmittance(ray, trafo, entity, depth, sampler, worker, tr),
            .Sphere => Sphere.transmittance(ray, trafo, entity, depth, sampler, worker, tr),
            .TriangleMesh => |m| m.transmittance(ray, trafo, entity, depth, sampler, worker, tr),
            else => true,
        };
    }

    pub fn scatter(
        self: *const Shape,
        ray: Ray,
        depth: u32,
        trafo: Trafo,
        throughput: Vec4f,
        entity: u32,
        sampler: *Sampler,
        worker: *Worker,
    ) Volume {
        return switch (self.*) {
            .Cube => Cube.scatter(ray, trafo, throughput, entity, depth, sampler, worker),
            .Sphere => Sphere.scatter(ray, trafo, throughput, entity, depth, sampler, worker),
            .TriangleMesh => |m| m.scatter(ray, trafo, throughput, entity, depth, sampler, worker),
            else => Volume.initPass(@splat(1.0)),
        };
    }

    pub fn sampleTo(
        self: *const Shape,
        part: u32,
        variant: u32,
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        two_sided: bool,
        total_sphere: bool,
        split_threshold: f32,
        sampler: *Sampler,
        buffer: *SamplesTo,
    ) []SampleTo {
        return switch (self.*) {
            .Canopy => Canopy.sampleTo(n, trafo, total_sphere, sampler, buffer),
            .Disk => Disk.sampleTo(p, n, trafo, two_sided, total_sphere, sampler, buffer),
            .DistantSphere => DistantSphere.sampleTo(n, trafo, total_sphere, sampler, buffer),
            .InfiniteSphere => InfiniteSphere.sampleTo(n, trafo, total_sphere, sampler, buffer),
            .Rectangle => Rectangle.sampleTo(p, n, trafo, two_sided, total_sphere, sampler, buffer),
            .Sphere => Sphere.sampleTo(p, n, trafo, total_sphere, sampler, buffer),
            .TriangleMesh => |m| m.sampleTo(
                part,
                variant,
                p,
                n,
                trafo,
                two_sided,
                total_sphere,
                split_threshold,
                sampler,
                buffer,
            ),
            else => buffer[0..0],
        };
    }

    pub fn sampleVolumeTo(self: *const Shape, part: u32, p: Vec4f, trafo: Trafo, sampler: *Sampler) ?SampleTo {
        _ = part;

        return switch (self.*) {
            .Cube => Cube.sampleVolumeTo(p, trafo, sampler),
            else => null,
        };
    }

    pub fn sampleToUv(
        self: *const Shape,
        part: u32,
        p: Vec4f,
        uv: Vec2f,
        trafo: Trafo,
        two_sided: bool,
    ) ?SampleTo {
        _ = part;

        return switch (self.*) {
            .Canopy => Canopy.sampleToUv(uv, trafo),
            .Disk => Disk.sampleToUv(p, uv, trafo, two_sided),
            .InfiniteSphere => InfiniteSphere.sampleToUv(uv, trafo),
            .Rectangle => Rectangle.sampleToUv(p, uv, trafo, two_sided),
            .Sphere => Sphere.sampleToUv(p, uv, trafo),
            else => null,
        };
    }

    pub fn sampleVolumeToUvw(self: *const Shape, part: u32, p: Vec4f, uvw: Vec4f, trafo: Trafo) ?SampleTo {
        _ = part;

        return switch (self.*) {
            .Cube => Cube.sampleVolumeToUvw(p, uvw, trafo),
            else => null,
        };
    }

    pub fn shadowRay(self: *const Shape, origin: Vec4f, sample: SampleTo) Ray {
        return switch (self.*) {
            .Canopy, .InfiniteSphere => Ray.init(origin, sample.wi, 0.0, ro.Ray_max_t),
            .DistantSphere => Ray.init(origin, sample.wi, 0.0, ro.Almost_ray_max_t),
            else => {
                const light_pos = ro.offsetRay(sample.p, sample.n);
                const shadow_axis = light_pos - origin;
                const shadow_len = math.length3(shadow_axis);
                return Ray.init(
                    origin,
                    shadow_axis / @as(Vec4f, @splat(shadow_len)),
                    0.0,
                    shadow_len,
                );
            },
        };
    }

    pub fn sampleFrom(
        self: *const Shape,
        part: u32,
        variant: u32,
        trafo: Trafo,
        cos_a: f32,
        two_sided: bool,
        sampler: *Sampler,
        uv: Vec2f,
        importance_uv: Vec2f,
        bounds: AABB,
        from_image: bool,
    ) ?SampleFrom {
        return switch (self.*) {
            .Canopy => Canopy.sampleFrom(trafo, uv, importance_uv, bounds),
            .Disk => Disk.sampleFrom(trafo, cos_a, two_sided, sampler, uv, importance_uv),
            .DistantSphere => DistantSphere.sampleFrom(trafo, uv, importance_uv, bounds),
            .InfiniteSphere => InfiniteSphere.sampleFrom(trafo, uv, importance_uv, bounds, from_image),
            .Rectangle => Rectangle.sampleFrom(trafo, two_sided, sampler, uv, importance_uv),
            .Sphere => Sphere.sampleFrom(trafo, uv, importance_uv),
            .TriangleMesh => |m| m.sampleFrom(
                part,
                variant,
                trafo,
                two_sided,
                sampler,
                uv,
                importance_uv,
            ),
            else => null,
        };
    }

    pub fn sampleVolumeFromUvw(self: *const Shape, part: u32, uvw: Vec4f, trafo: Trafo, importance_uv: Vec2f) ?SampleFrom {
        _ = part;

        return switch (self.*) {
            .Cube => Cube.sampleVolumeFromUvw(uvw, trafo, importance_uv),
            else => null,
        };
    }

    pub fn pdf(
        self: *const Shape,
        part: u32,
        variant: u32,
        dir: Vec4f,
        p: Vec4f,
        n: Vec4f,
        frag: *const Fragment,
        two_sided: bool,
        total_sphere: bool,
        split_threshold: f32,
    ) f32 {
        return switch (self.*) {
            .Canopy => 1.0 / (2.0 * std.math.pi),
            .Cube, .Plane => 0.0,
            .CurveMesh => 0.0,
            .Disk => Disk.pdf(dir, p, frag, two_sided),
            .DistantSphere => DistantSphere.pdf(frag.trafo),
            .InfiniteSphere => InfiniteSphere.pdf(total_sphere),
            .Rectangle => Rectangle.pdf(p, frag.trafo),
            .Sphere => Sphere.pdf(p, frag.trafo),
            .TriangleMesh => |m| m.pdf(part, variant, dir, p, n, frag, two_sided, total_sphere, split_threshold),
        };
    }

    pub fn pdfUv(self: *const Shape, dir: Vec4f, p: Vec4f, frag: *const Fragment, two_sided: bool) f32 {
        return switch (self.*) {
            .Canopy => 1.0 / (2.0 * std.math.pi),
            .Disk => Disk.pdf(dir, p, frag, two_sided),
            .InfiniteSphere => InfiniteSphere.pdfUv(frag),
            .Rectangle => Rectangle.pdfUv(dir, p, frag, two_sided),
            .Sphere => Sphere.pdfUv(dir, p, frag),
            else => 0.0,
        };
    }

    pub fn volumePdf(self: *const Shape, p: Vec4f, frag: *const Fragment) f32 {
        return switch (self.*) {
            .Cube => Cube.volumePdf(p, frag),
            else => 0.0,
        };
    }

    pub fn uvWeight(self: *const Shape, uv: Vec2f) f32 {
        return switch (self.*) {
            .Canopy => Canopy.uvWeight(uv),
            .Disk => Disk.uvWeight(uv),
            .InfiniteSphere => @sin(uv[1] * std.math.pi),
            else => 1.0,
        };
    }

    pub fn prepareSampling(
        self: *Shape,
        alloc: Allocator,
        prop: u32,
        part: u32,
        material: u32,
        builder: *LightTreeBuilder,
        scene: *const Scene,
        threads: *Threads,
    ) !u32 {
        return switch (self.*) {
            .TriangleMesh => |*m| try m.prepareSampling(alloc, prop, part, material, builder, scene, threads),
            else => 0,
        };
    }

    pub fn differentialSurface(self: *const Shape, primitive: u32) DifferentialSurface {
        return switch (self.*) {
            .TriangleMesh => |*m| m.differentialSurface(primitive),
            else => .{ .dpdu = .{ 1.0, 0.0, 0.0, 0.0 }, .dpdv = .{ 0.0, -1.0, 0.0, 0.0 } },
        };
    }
};
