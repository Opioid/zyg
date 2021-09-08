const Base = @import("../material_base.zig").Base;
const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Worker = @import("../../worker.zig").Worker;
const ts = @import("../../../image/texture/sampler.zig");
const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Material = struct {
    super: Base = undefined,

    color: Vec4f = undefined,

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: *Worker) Sample {
        const color = if (self.super.color_map.isValid()) ts.sample2D_3(self.super.color_map, rs.uv, worker.scene) else self.color;

        return Sample.init(rs, wo, color, Vec4f.init1(0.0));
    }
};
