const Scene = @import("../scene.zig").Scene;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Worker = @import("../worker.zig").Worker;
const shp = @import("../shape/sample.zig");
const SampleTo = shp.To;

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
        _ = self;
        _ = p;
        _ = n;
        _ = total_sphere;
        _ = sampler;
        _ = sampler_d;
        _ = worker;

        return null;
    }
};
