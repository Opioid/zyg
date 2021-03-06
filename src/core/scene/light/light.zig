const Scene = @import("../scene.zig").Scene;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Worker = @import("../worker.zig").Worker;
const Ray = @import("../ray.zig").Ray;
const Prop = @import("../prop/prop.zig").Prop;
const Intersection = @import("../prop/intersection.zig").Intersection;
const Filter = @import("../../image/texture/sampler.zig").Filter;
const shp = @import("../shape/sample.zig");
const SampleTo = shp.To;
const SampleFrom = shp.From;
const Transformation = @import("../composed_transformation.zig").ComposedTransformation;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Light = struct {
    pub const Volume_mask: u32 = 0x10000000;

    pub const Class = enum(u8) {
        Prop,
        PropImage,
        Volume,
        VolumeImage,
    };

    class: Class,
    two_sided: bool,
    variant: u16 = undefined,
    prop: u32,
    part: u32,
    extent: f32 = undefined,

    pub fn isLight(id: u32) bool {
        return Prop.Null != id;
    }

    pub fn isAreaLight(id: u32) bool {
        return 0 == (id & Volume_mask);
    }

    pub fn stripMask(id: u32) u32 {
        return ~Volume_mask & id;
    }

    pub fn finite(self: Light, scene: Scene) bool {
        return scene.propShape(self.prop).finite();
    }

    pub fn volumetric(self: Light) bool {
        return switch (self.class) {
            .Volume, .VolumeImage => true,
            else => false,
        };
    }

    pub fn prepareSampling(
        self: Light,
        alloc: Allocator,
        light_id: usize,
        time: u64,
        scene: *Scene,
        threads: *Threads,
    ) void {
        const volume = switch (self.class) {
            .Volume, .VolumeImage => true,
            else => false,
        };

        scene.propPrepareSampling(alloc, self.prop, self.part, light_id, time, volume, threads);
    }

    pub fn power(self: Light, average_radiance: Vec4f, scene_bb: AABB, scene: Scene) Vec4f {
        const extent = if (self.two_sided) 2.0 * self.extent else self.extent;

        const radiance = @splat(4, extent) * average_radiance;

        if (scene.propShape(self.prop).finite()) {
            return radiance;
        }

        return @splat(4, math.squaredLength3(scene_bb.extent())) * radiance;
    }

    pub fn sampleTo(
        self: Light,
        p: Vec4f,
        n: Vec4f,
        time: u64,
        total_sphere: bool,
        sampler: *Sampler,
        worker: *Worker,
    ) ?SampleTo {
        const trafo = worker.scene.propTransformationAt(self.prop, time);

        return switch (self.class) {
            .Prop => self.propSampleTo(
                p,
                n,
                trafo,
                total_sphere,
                sampler,
                worker,
            ),
            .PropImage => self.propImageSampleTo(
                p,
                n,
                trafo,
                total_sphere,
                sampler,
                worker,
            ),
            .Volume => self.volumeSampleTo(
                p,
                n,
                trafo,
                total_sphere,
                sampler,
                worker,
            ),
            .VolumeImage => self.volumeImageSampleTo(
                p,
                n,
                trafo,
                total_sphere,
                sampler,
                worker,
            ),
        };
    }

    pub fn sampleFrom(
        self: Light,
        time: u64,
        sampler: *Sampler,
        bounds: AABB,
        worker: *Worker,
    ) ?SampleFrom {
        const trafo = worker.scene.propTransformationAt(self.prop, time);

        return switch (self.class) {
            .Prop => self.propSampleFrom(trafo, sampler, bounds, worker),
            .PropImage => self.propImageSampleFrom(trafo, sampler, bounds, worker),
            .VolumeImage => self.volumeImageSampleFrom(trafo, sampler, worker),
            else => null,
        };
    }

    pub fn evaluateTo(self: Light, sample: SampleTo, filter: ?Filter, scene: Scene) Vec4f {
        const material = scene.propMaterial(self.prop, self.part);

        return material.evaluateRadiance(sample.wi, sample.n, sample.uvw, self.extent, filter, scene);
    }

    pub fn evaluateFrom(self: Light, sample: SampleFrom, filter: ?Filter, scene: Scene) Vec4f {
        const material = scene.propMaterial(self.prop, self.part);

        return material.evaluateRadiance(-sample.dir, sample.n, sample.uvw, self.extent, filter, scene);
    }

    pub fn pdf(self: Light, ray: Ray, n: Vec4f, isec: Intersection, total_sphere: bool, scene: Scene) f32 {
        const trafo = scene.propTransformationAt(self.prop, ray.time);

        return switch (self.class) {
            .Prop => self.propPdf(ray, n, isec, trafo, total_sphere, scene),
            .PropImage => self.propImagePdf(ray, isec, trafo, scene),
            .Volume => self.volumePdf(ray, isec, trafo, scene),
            .VolumeImage => self.volumeImagePdf(ray, isec, trafo, scene),
        };
    }

    fn propSampleTo(
        self: Light,
        p: Vec4f,
        n: Vec4f,
        trafo: Transformation,
        total_sphere: bool,
        sampler: *Sampler,
        worker: *Worker,
    ) ?SampleTo {
        const shape = worker.scene.propShape(self.prop);
        const result = shape.sampleTo(
            self.part,
            self.variant,
            p,
            n,
            trafo,
            self.extent,
            self.two_sided,
            total_sphere,
            sampler,
            &worker.rng,
        ) orelse return null;

        if (math.dot3(result.wi, n) > 0.0 or total_sphere) {
            return result;
        }

        return null;
    }

    fn propImageSampleTo(
        self: Light,
        p: Vec4f,
        n: Vec4f,
        trafo: Transformation,
        total_sphere: bool,
        sampler: *Sampler,
        worker: *Worker,
    ) ?SampleTo {
        const s2 = sampler.sample2D(&worker.rng);

        const material = worker.scene.propMaterial(self.prop, self.part);
        const rs = material.radianceSample(.{ s2[0], s2[1], 0.0, 0.0 });
        if (0.0 == rs.pdf()) {
            return null;
        }

        const shape = worker.scene.propShape(self.prop);
        // this pdf includes the uv weight which adjusts for texture distortion by the shape
        var result = shape.sampleToUv(
            self.part,
            p,
            .{ rs.uvw[0], rs.uvw[1] },
            trafo,
            self.extent,
            self.two_sided,
        ) orelse return null;

        result.mulAssignPdf(rs.pdf());

        if (math.dot3(result.wi, n) > 0.0 or total_sphere) {
            return result;
        }

        return null;
    }

    fn propSampleFrom(
        self: Light,
        trafo: Transformation,
        sampler: *Sampler,
        bounds: AABB,
        worker: *Worker,
    ) ?SampleFrom {
        const s4 = sampler.sample4D(&worker.rng);

        const uv = Vec2f{ s4[0], s4[1] };
        const importance_uv = Vec2f{ s4[2], s4[3] };

        const extent = if (self.two_sided) 2.0 * self.extent else self.extent;

        const cos_a = worker.scene.propMaterial(self.prop, self.part).super().emittance.cos_a;

        const shape = worker.scene.propShape(self.prop);
        return shape.sampleFrom(
            self.part,
            self.variant,
            trafo,
            extent,
            cos_a,
            self.two_sided,
            sampler,
            &worker.rng,
            uv,
            importance_uv,
            bounds,
            false,
        );
    }

    fn propImageSampleFrom(
        self: Light,
        trafo: Transformation,
        sampler: *Sampler,
        bounds: AABB,
        worker: *Worker,
    ) ?SampleFrom {
        const s4 = sampler.sample4D(&worker.rng);

        const material = worker.scene.propMaterial(self.prop, self.part);
        const rs = material.radianceSample(.{ s4[0], s4[1], 0.0, 0.0 });
        if (0.0 == rs.pdf()) {
            return null;
        }

        const importance_uv = Vec2f{ s4[2], s4[3] };

        const extent = if (self.two_sided) 2.0 * self.extent else self.extent;

        const cos_a = worker.scene.propMaterial(self.prop, self.part).super().emittance.cos_a;

        const shape = worker.scene.propShape(self.prop);
        // this pdf includes the uv weight which adjusts for texture distortion by the shape
        var result = shape.sampleFrom(
            self.part,
            self.variant,
            trafo,
            extent,
            cos_a,
            self.two_sided,
            sampler,
            &worker.rng,
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
        trafo: Transformation,
        total_sphere: bool,
        sampler: *Sampler,
        worker: *Worker,
    ) ?SampleTo {
        const shape = worker.scene.propShape(self.prop);
        const result = shape.sampleVolumeTo(
            self.part,
            p,
            trafo,
            self.extent,
            sampler,
            &worker.rng,
        ) orelse return null;

        if (math.dot3(result.wi, n) > 0.0 or total_sphere) {
            return result;
        }

        return null;
    }

    fn volumeImageSampleTo(
        self: Light,
        p: Vec4f,
        n: Vec4f,
        trafo: Transformation,
        total_sphere: bool,
        sampler: *Sampler,
        worker: *Worker,
    ) ?SampleTo {
        const material = worker.scene.propMaterial(self.prop, self.part);
        const rs = material.radianceSample(sampler.sample3D(&worker.rng));
        if (0.0 == rs.pdf()) {
            return null;
        }

        const shape = worker.scene.propShape(self.prop);
        var result = shape.sampleVolumeToUvw(
            self.part,
            p,
            rs.uvw,
            trafo,
            self.extent,
        ) orelse return null;

        if (math.dot3(result.wi, n) > 0.0 or total_sphere) {
            result.mulAssignPdf(rs.pdf());
            return result;
        }

        return null;
    }

    fn volumeImageSampleFrom(
        self: Light,
        trafo: Transformation,
        sampler: *Sampler,
        worker: *Worker,
    ) ?SampleFrom {
        const material = worker.scene.propMaterial(self.prop, self.part);
        const rs = material.radianceSample(sampler.sample3D(&worker.rng));
        if (0.0 == rs.pdf()) {
            return null;
        }

        const importance_uv = sampler.sample2D(&worker.rng);

        const shape = worker.scene.propShape(self.prop);

        var result = shape.sampleVolumeFromUvw(
            self.part,
            rs.uvw,
            trafo,
            self.extent,
            importance_uv,
        ) orelse return null;

        result.mulAssignPdf(rs.pdf());

        return result;
    }

    fn propPdf(
        self: Light,
        ray: Ray,
        n: Vec4f,
        isec: Intersection,
        trafo: Transformation,
        total_sphere: bool,
        scene: Scene,
    ) f32 {
        return isec.shape(scene).pdf(
            self.variant,
            ray,
            n,
            isec.geo,
            trafo,
            self.extent,
            self.two_sided,
            total_sphere,
        );
    }

    fn propImagePdf(self: Light, ray: Ray, isec: Intersection, trafo: Transformation, scene: Scene) f32 {
        const material = isec.material(scene);

        const uv = isec.geo.uv;
        const material_pdf = material.emissionPdf(.{ uv[0], uv[1], 0.0, 0.0 });

        // this pdf includes the uv weight which adjusts for texture distortion by the shape
        const shape_pdf = isec.shape(scene).pdfUv(ray, isec.geo, trafo, self.extent, self.two_sided);

        return material_pdf * shape_pdf;
    }

    fn volumePdf(
        self: Light,
        ray: Ray,
        isec: Intersection,
        trafo: Transformation,
        scene: Scene,
    ) f32 {
        return isec.shape(scene).volumePdf(ray, isec.geo, trafo, self.extent);
    }

    fn volumeImagePdf(
        self: Light,
        ray: Ray,
        isec: Intersection,
        trafo: Transformation,
        scene: Scene,
    ) f32 {
        const material_pdf = isec.material(scene).emissionPdf(isec.geo.p);
        const shape_pdf = isec.shape(scene).volumePdf(ray, isec.geo, trafo, self.extent);

        return material_pdf * shape_pdf;
    }
};
