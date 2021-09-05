const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Emittance = @import("../../light/emittance.zig").Emittance;
const Worker = @import("../../worker.zig").Worker;
const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Material = struct {
    emittance: Emittance = undefined,

    pub fn sample(self: Material, rs: Renderstate, wo: Vec4f, worker: *Worker) Sample {
        _ = self;

        const radiance = self.emittance.radiance(worker.scene.lightArea(rs.prop, rs.part));

        const fradiance = radiance;

        return Sample.init(rs, wo, fradiance);
    }
};
