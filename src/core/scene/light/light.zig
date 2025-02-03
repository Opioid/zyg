const Scene = @import("../scene.zig").Scene;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Prop = @import("../prop/prop.zig").Prop;
const Shape = @import("../shape/shape.zig").Shape;
const Vertex = @import("../vertex.zig").Vertex;
const Fragment = @import("../shape/intersection.zig").Fragment;
const shp = @import("../shape/sample.zig");
const SampleTo = shp.To;
const SampleFrom = shp.From;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Properties = struct {
    sphere: Vec4f,
    cone: Vec4f,
    power: f32,
    two_sided: bool,
};

pub const Light = struct {
    pub const Class = enum(u8) {
        Prop,
        PropImage,
        Volume,
        VolumeImage,
    };

    prop: u32 align(16),
    part: u32,
    variant: u32,
    class: Class,
    two_sided: bool,
    shadow_catcher_light: bool,

    pub fn isLight(id: u32) bool {
        return Prop.Null != id;
    }

    pub fn finite(self: Light, scene: *const Scene) bool {
        return scene.propShape(self.prop).finite();
    }

    pub fn volumetric(self: Light) bool {
        return switch (self.class) {
            .Volume, .VolumeImage => true,
            else => false,
        };
    }

    pub fn shadowCatcherLight(self: Light) bool {
        return self.shadow_catcher_light;
    }

    pub fn power(self: Light, average_radiance: Vec4f, extent: f32, scene_bb: AABB, scene: *const Scene) Vec4f {
        const radiance = @as(Vec4f, @splat(extent)) * average_radiance;

        if (scene.propShape(self.prop).finite() or scene_bb.empty()) {
            return radiance;
        }

        return @as(Vec4f, @splat(math.squaredLength3(scene_bb.extent()))) * radiance;
    }

    pub fn potentialMaxSamples(self: Light, scene: *const Scene) u32 {
        return switch (self.class) {
            .Prop => switch (scene.propShape(self.prop).*) {
                .TriangleMesh => Shape.MaxSamples,
                else => 1,
            },
            .PropImage => scene.propMaterial(self.prop, self.part).numSamples(std.math.floatMax(f32)),
            .Volume, .VolumeImage => 1,
        };
    }

    pub fn sampleTo(
        self: Light,
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        total_sphere: bool,
        split_threshold: f32,
        sampler: *Sampler,
        scene: *const Scene,
        buffer: *Scene.SamplesTo,
    ) []SampleTo {
        return switch (self.class) {
            .Prop => self.propSampleTo(p, n, trafo, total_sphere, split_threshold, sampler, scene, buffer),
            .PropImage => self.propSampleMaterialTo(p, n, trafo, total_sphere, split_threshold, sampler, scene, buffer),
            .Volume => self.volumeSampleTo(p, n, trafo, total_sphere, sampler, scene, buffer),
            .VolumeImage => self.volumeImageSampleTo(p, n, trafo, total_sphere, sampler, scene, buffer),
        };
    }

    pub fn sampleFrom(self: Light, time: u64, sampler: *Sampler, bounds: AABB, scene: *const Scene) ?SampleFrom {
        const trafo = scene.propTransformationAt(self.prop, time);

        return switch (self.class) {
            .Prop => self.propSampleFrom(trafo, sampler, bounds, scene),
            .PropImage => self.propImageSampleFrom(trafo, sampler, bounds, scene),
            .VolumeImage => self.volumeImageSampleFrom(trafo, sampler, scene),
            else => null,
        };
    }

    pub fn evaluateTo(self: Light, p: Vec4f, trafo: Trafo, sample: SampleTo, sampler: *Sampler, scene: *const Scene) Vec4f {
        const material = scene.propMaterial(self.prop, self.part);
        return material.evaluateRadiance(
            p,
            sample.wi,
            sample.n,
            sample.uvw,
            trafo,
            self.prop,
            self.part,
            sampler,
            scene,
        );
    }

    pub fn evaluateFrom(self: Light, p: Vec4f, sample: SampleFrom, sampler: *Sampler, scene: *const Scene) Vec4f {
        const material = scene.propMaterial(self.prop, self.part);
        return material.evaluateRadiance(
            p,
            -sample.dir,
            sample.n,
            sample.uvw,
            sample.trafo,
            self.prop,
            self.part,
            sampler,
            scene,
        );
    }

    pub fn pdf(self: Light, vertex: *const Vertex, frag: *const Fragment, split_threshold: f32, scene: *const Scene) f32 {
        return switch (self.class) {
            .Prop => self.propPdf(vertex, frag, split_threshold, scene),
            .PropImage => self.propMaterialPdf(vertex, frag, split_threshold, scene),
            .Volume => scene.propShape(self.prop).volumePdf(vertex.origin, frag),
            .VolumeImage => self.volumeImagePdf(vertex.probe.ray.direction, frag, scene),
        };
    }

    pub fn shadowRay(self: Light, origin: Vec4f, sample: SampleTo, scene: *const Scene) Ray {
        return scene.propShape(self.prop).shadowRay(origin, sample);
    }

    fn propSampleTo(
        self: Light,
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        total_sphere: bool,
        split_threshold: f32,
        sampler: *Sampler,
        scene: *const Scene,
        buffer: *Scene.SamplesTo,
    ) []SampleTo {
        const material = scene.propMaterial(self.prop, self.part);
        const shape = scene.propShape(self.prop);
        return shape.sampleTo(
            self.part,
            self.variant,
            p,
            n,
            trafo,
            self.two_sided,
            total_sphere,
            split_threshold,
            material,
            sampler,
            buffer,
        );
    }

    fn propSampleMaterialTo(
        self: Light,
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        total_sphere: bool,
        split_threshold: f32,
        sampler: *Sampler,
        scene: *const Scene,
        buffer: *Scene.SamplesTo,
    ) []SampleTo {
        const material = scene.propMaterial(self.prop, self.part);
        const shape = scene.propShape(self.prop);
        return shape.sampleMaterialTo(
            self.part,
            p,
            n,
            trafo,
            self.two_sided,
            total_sphere,
            split_threshold,
            material,
            sampler,
            buffer,
        );
    }

    fn propSampleFrom(self: Light, trafo: Trafo, sampler: *Sampler, bounds: AABB, scene: *const Scene) ?SampleFrom {
        const s4 = sampler.sample4D();

        const uv = Vec2f{ s4[0], s4[1] };
        const importance_uv = Vec2f{ s4[2], s4[3] };

        const cos_a = scene.propMaterial(self.prop, self.part).emissionAngle();

        const shape = scene.propShape(self.prop);
        return shape.sampleFrom(
            self.part,
            self.variant,
            trafo,
            cos_a,
            self.two_sided,
            sampler,
            uv,
            importance_uv,
            bounds,
            false,
        );
    }

    fn propImageSampleFrom(self: Light, trafo: Trafo, sampler: *Sampler, bounds: AABB, scene: *const Scene) ?SampleFrom {
        const s4 = sampler.sample4D();

        const material = scene.propMaterial(self.prop, self.part);
        const rs = material.radianceSample(.{ s4[0], s4[1], 0.0, 0.0 });
        if (0.0 == rs.pdf()) {
            return null;
        }

        const importance_uv = Vec2f{ s4[2], s4[3] };

        const cos_a = scene.propMaterial(self.prop, self.part).emissionAngle();

        const shape = scene.propShape(self.prop);

        // this pdf includes the uv weight which adjusts for texture distortion by the shape
        var result = shape.sampleFrom(
            self.part,
            self.variant,
            trafo,
            cos_a,
            self.two_sided,
            sampler,
            .{ rs.uvw[0], rs.uvw[1] },
            importance_uv,
            bounds,
            true,
        ) orelse return null;

        result.mulAssignPdf(rs.pdf());

        return result;
    }

    fn volumeSampleTo(
        self: Light,
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        total_sphere: bool,
        sampler: *Sampler,
        scene: *const Scene,
        buffer: *Scene.SamplesTo,
    ) []SampleTo {
        const shape = scene.propShape(self.prop);
        const result = shape.sampleVolumeTo(self.part, p, trafo, sampler) orelse return buffer[0..0];

        if (math.dot3(result.wi, n) > 0.0 or total_sphere) {
            buffer[0] = result;
            return buffer[0..1];
        }

        return buffer[0..0];
    }

    fn volumeImageSampleTo(
        self: Light,
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        total_sphere: bool,
        sampler: *Sampler,
        scene: *const Scene,
        buffer: *Scene.SamplesTo,
    ) []SampleTo {
        const material = scene.propMaterial(self.prop, self.part);
        const rs = material.radianceSample(sampler.sample3D());
        if (0.0 == rs.pdf()) {
            return buffer[0..0];
        }

        const shape = scene.propShape(self.prop);
        var result = shape.sampleVolumeToUvw(self.part, p, rs.uvw, trafo) orelse return buffer[0..0];

        if (math.dot3(result.wi, n) > 0.0 or total_sphere) {
            result.mulAssignPdf(rs.pdf());
            buffer[0] = result;
            return buffer[0..1];
        }

        return buffer[0..0];
    }

    fn volumeImageSampleFrom(self: Light, trafo: Trafo, sampler: *Sampler, scene: *const Scene) ?SampleFrom {
        const material = scene.propMaterial(self.prop, self.part);
        const rs = material.radianceSample(sampler.sample3D());
        if (0.0 == rs.pdf()) {
            return null;
        }

        const importance_uv = sampler.sample2D();

        const shape = scene.propShape(self.prop);
        var result = shape.sampleVolumeFromUvw(self.part, rs.uvw, trafo, importance_uv) orelse return null;

        result.mulAssignPdf(rs.pdf());

        return result;
    }

    fn propPdf(self: Light, vertex: *const Vertex, frag: *const Fragment, split_threshold: f32, scene: *const Scene) f32 {
        const total_sphere = vertex.state.is_translucent;
        const material = frag.material(scene);

        return scene.propShape(self.prop).pdf(
            self.part,
            self.variant,
            vertex.probe.ray.direction,
            vertex.origin,
            vertex.geo_n,
            frag,
            total_sphere,
            split_threshold,
            material,
        );
    }

    fn propMaterialPdf(self: Light, vertex: *const Vertex, frag: *const Fragment, split_threshold: f32, scene: *const Scene) f32 {
        const material = frag.material(scene);
        return scene.propShape(self.prop).materialPdf(
            vertex.probe.ray.direction,
            vertex.origin,
            frag,
            split_threshold,
            material,
        );
    }

    fn volumeImagePdf(self: Light, p: Vec4f, frag: *const Fragment, scene: *const Scene) f32 {
        const material_pdf = frag.material(scene).emissionPdf(frag.uvw);
        const shape_pdf = scene.propShape(self.prop).volumePdf(p, frag);
        return material_pdf * shape_pdf;
    }
};
