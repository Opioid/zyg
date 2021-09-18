const Base = @import("../material_base.zig").Base;
const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Emittance = @import("../../light/emittance.zig").Emittance;
const Worker = @import("../../worker.zig").Worker;
const ts = @import("../../../image/texture/sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Material = struct {
    super: Base = undefined,

    emission_map: Texture = undefined,
    emittance: Emittance = undefined,
    emission_factor: f32 = undefined,

    pub fn init(two_sided: bool) Material {
        return .{ .super = Base.init(two_sided) };
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: *Worker) Sample {
        var radiance: Vec4f = undefined;

        if (self.emission_map.isValid()) {
            const ef = @splat(4, self.emission_factor);
            radiance = ef * ts.sample2D_3(self.emission_map, rs.uv, worker.scene);
        } else {
            radiance = self.emittance.radiance(worker.scene.lightArea(rs.prop, rs.part));
        }

        return Sample.init(rs, wo, radiance);
    }
};
