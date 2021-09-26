const Scene = @import("../scene.zig").Scene;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Worker = @import("../worker.zig").Worker;
const Filter = @import("../../image/texture/sampler.zig").Filter;
const shp = @import("../shape/sample.zig");
const SampleTo = shp.To;
const Transformation = @import("../composed_transformation.zig").ComposedTransformation;

const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Light = packed struct {
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

    pub fn prepareSampling(self: Light, light_id: usize, scene: *Scene) void {
        scene.propPrepareSampling(self.prop, self.part, light_id);
    }

    pub fn sampleTo(
        self: Light,
        p: Vec4f,
        n: Vec4f,
        total_sphere: bool,
        sampler: *Sampler,
        sampler_d: usize,
        worker: *Worker,
    ) ?SampleTo {
        const trafo = worker.scene.propTransformationAt(self.prop);

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
            else => null,
        };
    }

    pub fn evaluateTo(self: Light, sample: SampleTo, filter: ?Filter, worker: Worker) Vec4f {
        const material = worker.scene.propMaterial(self.prop, self.part);

        return material.evaluateRadiance(sample.wi, sample.n, sample.uvw, self.extent, filter, worker);
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
};
