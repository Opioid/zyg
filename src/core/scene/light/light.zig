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
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Light = struct {
    pub const Volume_mask: u32 = 0x10000000;

    pub const Type = enum(u8) {
        Prop,
        PropImage,
        Volume,
        VolumeImage,
    };

    typef: Type,
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

    pub fn isFinite(self: Light, scene: Scene) bool {
        return scene.propShape(self.prop).isFinite();
    }

    pub fn prepareSampling(
        self: Light,
        alloc: Allocator,
        light_id: usize,
        time: u64,
        scene: *Scene,
        worker: Worker,
        threads: *Threads,
    ) void {
        const volume = switch (self.typef) {
            .Volume, .VolumeImage => true,
            else => false,
        };

        scene.propPrepareSampling(alloc, self.prop, self.part, light_id, time, volume, worker, threads);
    }

    pub fn power(self: Light, average_radiance: Vec4f, scene_bb: AABB, scene: Scene) Vec4f {
        const extent = if (self.two_sided) 2.0 * self.extent else self.extent;

        const radiance = @splat(4, extent) * average_radiance;

        if (scene.propShape(self.prop).isFinite()) {
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
        sampler_d: usize,
        worker: *Worker,
    ) ?SampleTo {
        const trafo = worker.scene.propTransformationAt(self.prop, time);

        return switch (self.typef) {
            .Prop => self.propSampleTo(
                p,
                n,
                trafo,
                total_sphere,
                sampler,
                sampler_d,
                worker,
            ),
            .PropImage => self.propImageSampleTo(
                p,
                n,
                trafo,
                total_sphere,
                sampler,
                sampler_d,
                worker,
            ),
            .Volume => self.volumeSampleTo(
                p,
                n,
                trafo,
                total_sphere,
                sampler,
                sampler_d,
                worker,
            ),
            else => null,
        };
    }

    pub fn sampleFrom(
        self: Light,
        time: u64,
        sampler: *Sampler,
        sampler_d: usize,
        bounds: AABB,
        worker: *Worker,
    ) ?SampleFrom {
        const trafo = worker.scene.propTransformationAt(self.prop, time);

        return switch (self.typef) {
            .Prop => self.propSampleFrom(
                trafo,
                sampler,
                sampler_d,
                bounds,
                worker,
            ),
            .PropImage => self.propImageSampleFrom(
                trafo,
                sampler,
                sampler_d,
                bounds,
                worker,
            ),
            else => null,
        };
    }

    pub fn evaluateTo(self: Light, sample: SampleTo, filter: ?Filter, worker: Worker) Vec4f {
        const material = worker.scene.propMaterial(self.prop, self.part);

        return material.evaluateRadiance(sample.wi, sample.n, sample.uvw, self.extent, filter, worker);
    }

    pub fn evaluateFrom(self: Light, sample: SampleFrom, filter: ?Filter, worker: Worker) Vec4f {
        const material = worker.scene.propMaterial(self.prop, self.part);

        const uvw = Vec4f{ sample.uv[0], sample.uv[1], 0.0, 0.0 };

        return material.evaluateRadiance(-sample.dir, sample.n, uvw, self.extent, filter, worker);
    }

    pub fn pdf(self: Light, ray: Ray, n: Vec4f, isec: Intersection, total_sphere: bool, worker: Worker) f32 {
        const trafo = worker.scene.propTransformationAt(self.prop, ray.time);

        return switch (self.typef) {
            .Prop => self.propPdf(ray, n, isec, trafo, total_sphere, worker),
            .PropImage => self.propImagePdf(ray, isec, trafo, worker),
            .Volume => self.volumePdf(ray, isec, trafo, worker),
            else => 0.0,
        };
    }

    fn propSampleTo(
        self: Light,
        p: Vec4f,
        n: Vec4f,
        trafo: Transformation,
        total_sphere: bool,
        sampler: *Sampler,
        sampler_d: usize,
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
            sampler_d,
        ) orelse return null;

        if (math.dot3(result.wi, n) > 0.0 or total_sphere) {
            return result;
        }

        return null;
    }

    fn propSampleFrom(
        self: Light,
        trafo: Transformation,
        sampler: *Sampler,
        sampler_d: usize,
        bounds: AABB,
        worker: *Worker,
    ) ?SampleFrom {
        const importance_uv = sampler.sample2D(&worker.rng, 0);

        const extent = if (self.two_sided) 2.0 * self.extent else self.extent;

        const shape = worker.scene.propShape(self.prop);
        return shape.sampleFrom(
            self.part,
            self.variant,
            trafo,
            extent,
            self.two_sided,
            sampler,
            &worker.rng,
            sampler_d,
            importance_uv,
            bounds,
        );
    }

    fn propImageSampleTo(
        self: Light,
        p: Vec4f,
        n: Vec4f,
        trafo: Transformation,
        total_sphere: bool,
        sampler: *Sampler,
        sampler_d: usize,
        worker: *Worker,
    ) ?SampleTo {
        const s2d = sampler.sample2D(&worker.rng, sampler_d);

        const material = worker.scene.propMaterial(self.prop, self.part);
        const rs = material.radianceSample(.{ s2d[0], s2d[1], 0.0, 0.0 });
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

    fn propImageSampleFrom(
        self: Light,
        trafo: Transformation,
        sampler: *Sampler,
        sampler_d: usize,
        bounds: AABB,
        worker: *Worker,
    ) ?SampleFrom {
        const s2d = sampler.sample2D(&worker.rng, sampler_d);

        const material = worker.scene.propMaterial(self.prop, self.part);
        const rs = material.radianceSample(.{ s2d[0], s2d[1], 0.0, 0.0 });
        if (0.0 == rs.pdf()) {
            return null;
        }

        const importance_uv = sampler.sample2D(&worker.rng, 0);

        const shape = worker.scene.propShape(self.prop);
        // this pdf includes the uv weight which adjusts for texture distortion by the shape
        var result = shape.sampleFromUv(
            self.part,
            .{ rs.uvw[0], rs.uvw[1] },
            trafo,
            self.extent,
            self.two_sided,
            sampler,
            &worker.rng,
            sampler_d,
            importance_uv,
            bounds,
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
        sampler_d: usize,
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
            sampler_d,
        ) orelse return null;

        if (math.dot3(result.wi, n) > 0.0 or total_sphere) {
            return result;
        }

        return null;
    }

    fn propPdf(
        self: Light,
        ray: Ray,
        n: Vec4f,
        isec: Intersection,
        trafo: Transformation,
        total_sphere: bool,
        worker: Worker,
    ) f32 {
        const two_sided = isec.material(worker).twoSided();

        return isec.shape(worker).pdf(
            self.variant,
            ray,
            n,
            isec.geo,
            trafo,
            self.extent,
            two_sided,
            total_sphere,
        );
    }

    fn propImagePdf(self: Light, ray: Ray, isec: Intersection, trafo: Transformation, worker: Worker) f32 {
        const material = isec.material(worker);
        const two_sided = material.twoSided();

        const uv = isec.geo.uv;
        const material_pdf = material.emissionPdf(.{ uv[0], uv[1], 0.0, 0.0 });

        // this pdf includes the uv weight which adjusts for texture distortion by the shape
        const shape_pdf = isec.shape(worker).pdfUv(ray, isec.geo, trafo, self.extent, two_sided);

        return material_pdf * shape_pdf;
    }

    fn volumePdf(
        self: Light,
        ray: Ray,
        isec: Intersection,
        trafo: Transformation,
        worker: Worker,
    ) f32 {
        return isec.shape(worker).volumePdf(
            ray,
            isec.geo,
            trafo,
            self.extent,
        );
    }
};
