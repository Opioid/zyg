pub const Canopy = @import("canopy.zig").Canopy;
pub const Cube = @import("cube.zig").Cube;
pub const CurveMesh = @import("curve/curve_mesh.zig").Mesh;
pub const Disk = @import("disk.zig").Disk;
pub const Distant = @import("distant.zig").Distant;
pub const Dome = @import("dome.zig").Dome;
pub const PointMotionCloud = @import("point/point_motion_cloud.zig").MotionCloud;
pub const Rectangle = @import("rectangle.zig").Rectangle;
pub const Sphere = @import("sphere.zig").Sphere;
pub const TriangleMesh = @import("triangle/triangle_mesh.zig").Mesh;
pub const TriangleMotionMesh = @import("triangle/triangle_motion_mesh.zig").MotionMesh;
const ro = @import("../ray_offset.zig");
const Material = @import("../material/material.zig").Material;
const Context = @import("../context.zig").Context;
const Scene = @import("../scene.zig").Scene;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
pub const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Volume = int.Volume;
const DifferentialSurface = int.DifferentialSurface;
pub const Probe = @import("probe.zig").Probe;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const ShapeSampler = @import("shape_sampler.zig").Sampler;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Vertex = @import("../vertex.zig").Vertex;
const LightTreeBuilder = @import("../light/light_tree_builder.zig").Builder;

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
    Distant: Distant,
    Dome: Dome,
    PointMotionCloud: PointMotionCloud,
    Rectangle: Rectangle,
    Sphere: Sphere,
    TriangleMesh: TriangleMesh,
    TriangleMotionMesh: TriangleMotionMesh,

    pub fn deinit(self: *Shape, alloc: Allocator) void {
        switch (self.*) {
            inline .CurveMesh, .PointMotionCloud, .TriangleMesh, .TriangleMotionMesh => |*m| m.deinit(alloc),
            else => {},
        }
    }

    pub fn frameDependant(self: *const Shape) bool {
        return switch (self.*) {
            .PointMotionCloud, .TriangleMotionMesh => true,
            else => false,
        };
    }

    pub fn numParts(self: *const Shape) u32 {
        return switch (self.*) {
            inline .TriangleMesh, .TriangleMotionMesh => |m| m.numParts(),
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
            inline .TriangleMesh, .TriangleMotionMesh => |m| m.partMaterialId(part),
            else => part,
        };
    }

    pub fn finite(self: *const Shape) bool {
        return switch (self.*) {
            .Canopy, .Distant, .Dome => false,
            else => true,
        };
    }

    pub fn analytical(self: *const Shape) bool {
        return switch (self.*) {
            .CurveMesh, .PointMotionCloud, .TriangleMesh, .TriangleMotionMesh => false,
            else => true,
        };
    }

    pub fn aabb(self: *const Shape) AABB {
        return switch (self.*) {
            .Canopy, .Distant, .Dome => .empty,
            .Disk, .Rectangle => AABB.init(.{ -0.5, -0.5, 0.0, 0.0 }, .{ 0.5, 0.5, 0.0, 0.0 }),
            .Cube, .Sphere => AABB.init(@splat(-0.5), @splat(0.5)),
            inline .CurveMesh, .PointMotionCloud, .TriangleMesh, .TriangleMotionMesh => |m| m.tree.aabb(),
        };
    }

    pub fn cone(self: *const Shape) Vec4f {
        return switch (self.*) {
            .Disk, .Rectangle, .Distant => .{ 0.0, 0.0, 1.0, 1.0 },
            else => .{ 0.0, 0.0, 1.0, -1.0 },
        };
    }

    pub fn partAabb(self: *const Shape, part: u32, variant: u32) AABB {
        return switch (self.*) {
            .TriangleMesh => |m| m.partAabb(part, variant),
            else => self.aabb(),
        };
    }

    pub fn partCone(self: *const Shape, part: u32, variant: u32) Vec4f {
        return switch (self.*) {
            .TriangleMesh => |m| m.partCone(part, variant),
            else => self.cone(),
        };
    }

    pub fn area(self: *const Shape, part: u32, scale: Vec4f) f32 {
        return switch (self.*) {
            .Canopy => 2.0 * std.math.pi,
            .Cube => return 2.0 * (scale[0] * scale[1] + scale[0] * scale[2] + scale[1] * scale[2]),
            .CurveMesh => 0.0,
            .Disk => std.math.pi * math.pow2(0.5 * scale[0]),

            // This calculates the solid angle, not the area!
            // I think it is what we actually need for the PDF, but results are extremely close
            .Distant => Distant.solidAngle(scale[0]),

            .Dome => 4.0 * std.math.pi,
            .PointMotionCloud => |c| c.area(scale),
            .Rectangle => scale[0] * scale[1],
            .Sphere => (4.0 * std.math.pi) * math.pow2(0.5 * scale[0]),
            .TriangleMesh => |m| m.area(part, scale),
            .TriangleMotionMesh => 0.0,
        };
    }

    pub fn volume(self: *const Shape, scale: Vec4f) f32 {
        return switch (self.*) {
            .Cube => return scale[0] * scale[1] * scale[2],
            else => 0.0,
        };
    }

    pub fn intersect(self: *const Shape, probe: Probe, trafo: Trafo, isec: *Intersection) bool {
        return switch (self.*) {
            .Canopy => Canopy.intersect(probe.ray, trafo, isec),
            .Cube => Cube.intersect(probe.ray, trafo, isec),
            .CurveMesh => |m| m.intersect(probe.ray, trafo, isec),
            .Disk => Disk.intersect(probe.ray, trafo, isec),
            .Distant => Distant.intersect(probe.ray, trafo, isec),
            .Dome => Dome.intersect(probe.ray, trafo, isec),
            .PointMotionCloud => |c| c.intersect(probe, trafo, isec),
            .Rectangle => Rectangle.intersect(probe.ray, trafo, isec),
            .Sphere => Sphere.intersect(probe.ray, trafo, isec),
            .TriangleMesh => |m| m.intersect(probe.ray, trafo, isec),
            .TriangleMotionMesh => |m| m.intersect(probe, trafo, isec),
        };
    }

    pub fn intersectOpacity(
        self: *const Shape,
        probe: Probe,
        trafo: Trafo,
        entity: u32,
        sampler: *Sampler,
        scene: *const Scene,
        isec: *Intersection,
    ) bool {
        return switch (self.*) {
            .Canopy => Canopy.intersect(probe.ray, trafo, isec),
            .Cube => Cube.intersect(probe.ray, trafo, isec),
            .CurveMesh => |m| m.intersect(probe.ray, trafo, isec),
            .Disk => Disk.intersectOpacity(probe.ray, trafo, entity, sampler, scene, isec),
            .Distant => Distant.intersect(probe.ray, trafo, isec),
            .Dome => Dome.intersect(probe.ray, trafo, isec),
            .PointMotionCloud => |c| c.intersect(probe, trafo, isec),
            .Rectangle => Rectangle.intersectOpacity(probe.ray, trafo, entity, sampler, scene, isec),
            .Sphere => Sphere.intersectOpacity(probe.ray, trafo, entity, sampler, scene, isec),
            .TriangleMesh => |m| m.intersectOpacity(probe.ray, trafo, entity, sampler, scene, isec),
            .TriangleMotionMesh => |m| m.intersectOpacity(probe, trafo, entity, sampler, scene, isec),
        };
    }

    pub fn fragment(self: *const Shape, probe: Probe, frag: *Fragment) void {
        switch (self.*) {
            .Canopy => Canopy.fragment(probe.ray, frag),
            .Cube => Cube.fragment(probe.ray, frag),
            .CurveMesh => |m| m.fragment(probe.ray, frag),
            .Disk => Disk.fragment(probe.ray, frag),
            .Distant => Distant.fragment(probe.ray, frag),
            .Dome => Dome.fragment(probe.ray, frag),
            .PointMotionCloud => |c| c.fragment(probe, frag),
            .Rectangle => Rectangle.fragment(probe.ray, frag),
            .Sphere => Sphere.fragment(probe.ray, frag),
            .TriangleMesh => |m| m.fragment(frag),
            .TriangleMotionMesh => |m| m.fragment(probe.time, frag),
        }
    }

    pub fn intersectP(self: *const Shape, probe: Probe, trafo: Trafo) bool {
        return switch (self.*) {
            .Cube => Cube.intersectP(probe.ray, trafo),
            .CurveMesh => |m| m.intersectP(probe.ray, trafo),
            .Disk => Disk.intersectP(probe.ray, trafo),
            .PointMotionCloud => |c| c.intersectP(probe, trafo),
            .Rectangle => Rectangle.intersectP(probe.ray, trafo),
            .Sphere => Sphere.intersectP(probe.ray, trafo),
            .TriangleMesh => |m| m.intersectP(probe.ray, trafo),
            .TriangleMotionMesh => |m| m.intersectP(probe, trafo),
            else => false,
        };
    }

    pub fn visibility(self: *const Shape, probe: Probe, trafo: Trafo, entity: u32, sampler: *Sampler, context: Context, tr: *Vec4f) bool {
        return switch (self.*) {
            .Cube => Cube.visibility(probe.ray, trafo, entity, sampler, context, tr),
            .Disk => Disk.visibility(probe.ray, trafo, entity, sampler, context, tr),
            .Rectangle => Rectangle.visibility(probe.ray, trafo, entity, sampler, context, tr),
            .Sphere => Sphere.visibility(probe.ray, trafo, entity, sampler, context, tr),
            .TriangleMesh => |m| m.visibility(probe.ray, trafo, entity, sampler, context, tr),
            .TriangleMotionMesh => |m| m.visibility(probe, trafo, entity, sampler, context, tr),
            else => true,
        };
    }

    pub fn transmittance(
        self: *const Shape,
        probe: Probe,
        trafo: Trafo,
        entity: u32,
        sampler: *Sampler,
        context: Context,
        tr: *Vec4f,
    ) bool {
        return switch (self.*) {
            .Cube => Cube.transmittance(probe, trafo, entity, sampler, context, tr),
            .Sphere => Sphere.transmittance(probe, trafo, entity, sampler, context, tr),
            .TriangleMesh => |m| m.transmittance(probe, trafo, entity, sampler, context, tr),
            //  .TriangleMotionMesh => |m| m.transmittance(probe, trafo, entity, sampler, context, tr),
            else => true,
        };
    }

    pub fn scatter(
        self: *const Shape,
        probe: Probe,
        trafo: Trafo,
        throughput: Vec4f,
        entity: u32,
        sampler: *Sampler,
        context: Context,
    ) Volume {
        return switch (self.*) {
            .Cube => Cube.scatter(probe, trafo, throughput, entity, sampler, context),
            .Sphere => Sphere.scatter(probe, trafo, throughput, entity, sampler, context),
            .TriangleMesh => |m| m.scatter(probe, trafo, throughput, entity, sampler, context),
            //  .TriangleMotionMesh => |m| m.scatter(probe, trafo, throughput, entity, sampler, context),
            else => Volume.initPass(@splat(1.0)),
        };
    }

    pub fn emission(
        self: *const Shape,
        vertex: *const Vertex,
        frag: *Fragment,
        sampler: *Sampler,
        context: Context,
    ) Vec4f {
        return switch (self.*) {
            .Disk => Disk.emission(vertex, frag, sampler, context),
            .PointMotionCloud => |c| c.emission(vertex, frag, sampler, context),
            .Rectangle => Rectangle.emission(vertex, frag, sampler, context),
            .Sphere => Sphere.emission(vertex, frag, sampler, context),
            .TriangleMesh => |m| m.emission(vertex, frag, sampler, context),
            .TriangleMotionMesh => |m| m.emission(vertex, frag, sampler, context),
            else => @splat(0.0),
        };
    }

    pub fn sampleTo(
        self: *const Shape,
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        time: u64,
        part: u32,
        two_sided: bool,
        total_sphere: bool,
        split_threshold: f32,
        shape_sampler: *const ShapeSampler,
        sampler: *Sampler,
        buffer: *SamplesTo,
    ) []SampleTo {
        return switch (self.*) {
            .Canopy => Canopy.sampleTo(n, trafo, total_sphere, sampler, buffer),
            .Disk => Disk.sampleTo(p, n, trafo, two_sided, total_sphere, split_threshold, shape_sampler, sampler, buffer),
            .Distant => Distant.sampleTo(n, trafo, total_sphere, sampler, buffer),
            .Dome => Dome.sampleTo(n, trafo, total_sphere, sampler, buffer),
            .PointMotionCloud => |c| c.sampleTo(p, n, trafo, time, total_sphere, split_threshold, shape_sampler, sampler, buffer),
            .Rectangle => Rectangle.sampleTo(p, n, trafo, two_sided, total_sphere, split_threshold, shape_sampler, sampler, buffer),
            .Sphere => Sphere.sampleTo(p, n, trafo, total_sphere, split_threshold, shape_sampler, sampler, buffer),
            .TriangleMesh => |m| m.sampleTo(
                part,
                p,
                n,
                trafo,
                two_sided,
                total_sphere,
                split_threshold,
                shape_sampler,
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

    pub fn sampleMaterialTo(
        self: *const Shape,
        part: u32,
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        two_sided: bool,
        total_sphere: bool,
        split_threshold: f32,
        shape_sampler: *const ShapeSampler,
        sampler: *Sampler,
        buffer: *SamplesTo,
    ) []SampleTo {
        _ = part;

        return switch (self.*) {
            .Canopy => Canopy.sampleMaterialTo(n, trafo, total_sphere, shape_sampler, sampler, buffer),
            .Disk => Disk.sampleMaterialTo(p, n, trafo, two_sided, total_sphere, split_threshold, shape_sampler, sampler, buffer),
            .Dome => Dome.sampleMaterialTo(n, trafo, total_sphere, split_threshold, shape_sampler, sampler, buffer),
            .Rectangle => Rectangle.sampleMaterialTo(p, n, trafo, two_sided, total_sphere, split_threshold, shape_sampler, sampler, buffer),
            .Sphere => Sphere.sampleMaterialTo(p, n, trafo, total_sphere, shape_sampler, sampler, buffer),
            else => buffer[0..0],
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
            .Canopy, .Distant, .Dome => Ray.init(origin, sample.wi, 0.0, ro.RayMaxT),
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
        trafo: Trafo,
        time: u64,
        uv: Vec2f,
        importance_uv: Vec2f,
        part: u32,
        cos_a: f32,
        two_sided: bool,
        shape_sampler: *const ShapeSampler,
        sampler: *Sampler,
        bounds: AABB,
        from_image: bool,
    ) ?SampleFrom {
        return switch (self.*) {
            .Canopy => Canopy.sampleFrom(trafo, uv, importance_uv, bounds),
            .Disk => Disk.sampleFrom(trafo, uv, importance_uv, cos_a, two_sided, sampler, from_image),
            .Distant => Distant.sampleFrom(trafo, uv, importance_uv, bounds),
            .Dome => Dome.sampleFrom(trafo, uv, importance_uv, bounds, from_image),
            .PointMotionCloud => |c| c.sampleFrom(trafo, time, uv, importance_uv, sampler),
            .Rectangle => Rectangle.sampleFrom(trafo, uv, importance_uv, two_sided, sampler),
            .Sphere => Sphere.sampleFrom(trafo, uv, importance_uv),
            .TriangleMesh => |m| m.sampleFrom(
                trafo,
                uv,
                importance_uv,
                part,
                two_sided,
                shape_sampler,
                sampler,
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
        dir: Vec4f,
        p: Vec4f,
        n: Vec4f,
        frag: *const Fragment,
        time: u64,
        total_sphere: bool,
        split_threshold: f32,
        shape_sampler: *const ShapeSampler,
    ) f32 {
        return switch (self.*) {
            .Canopy => 1.0 / (2.0 * std.math.pi),
            .Disk => Disk.pdf(dir, p, frag, split_threshold, shape_sampler),
            .Distant => Distant.pdf(frag.isec.trafo),
            .Dome => Dome.pdf(total_sphere),
            .PointMotionCloud => |c| c.pdf(dir, p, frag, time, split_threshold),
            .Rectangle => Rectangle.pdf(dir, p, frag, split_threshold, shape_sampler),
            .Sphere => Sphere.pdf(p, frag.isec.trafo, split_threshold, shape_sampler),
            .TriangleMesh => |m| m.pdf(dir, p, n, frag, total_sphere, split_threshold, shape_sampler),
            else => 0.0,
        };
    }

    pub fn materialPdf(
        self: *const Shape,
        dir: Vec4f,
        p: Vec4f,
        frag: *const Fragment,
        split_threshold: f32,
        shape_sampler: *const ShapeSampler,
    ) f32 {
        return switch (self.*) {
            .Canopy => shape_sampler.impl.pdf(frag.uvw) / (2.0 * std.math.pi),
            .Disk => Disk.materialPdf(dir, p, frag, split_threshold, shape_sampler),
            .Dome => Dome.materialPdf(frag, split_threshold, shape_sampler),
            .Rectangle => Rectangle.materialPdf(dir, p, frag, split_threshold, shape_sampler),
            .Sphere => Sphere.materialPdf(dir, p, frag, shape_sampler),
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
            .Dome => @sin(uv[1] * std.math.pi),
            else => 1.0,
        };
    }

    pub fn hasShapeSampler(self: *Shape) bool {
        return switch (self.*) {
            .TriangleMesh => true,
            else => false,
        };
    }

    pub fn prepareSampling(
        self: *Shape,
        alloc: Allocator,
        part: u32,
        material: u32,
        builder: *LightTreeBuilder,
        scene: *const Scene,
        threads: *Threads,
    ) !?ShapeSampler {
        return switch (self.*) {
            .TriangleMesh => |*m| try m.prepareSampling(alloc, part, material, builder, scene, threads),
            else => null,
        };
    }

    pub fn surfaceDifferentials(self: *const Shape, primitive: u32, trafo: Trafo, time: u64) DifferentialSurface {
        return switch (self.*) {
            .Rectangle => Rectangle.surfaceDifferentials(trafo),
            .TriangleMesh => |m| m.surfaceDifferentials(primitive, trafo),
            .TriangleMotionMesh => |m| m.surfaceDifferentials(primitive, trafo, time),
            else => .{
                .dpdu = @as(Vec4f, @splat(-trafo.scaleX())) * trafo.rotation.r[0],
                .dpdv = @as(Vec4f, @splat(-trafo.scaleY())) * trafo.rotation.r[1],
            },
        };
    }
};
