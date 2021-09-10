const Base = @import("../material_base.zig").Base;
const hlp = @import("../material_helper.zig");
const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Worker = @import("../../worker.zig").Worker;
const ts = @import("../../../image/texture/sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const math = @import("base").math;
const Vec4f = math.Vec4f;

//const std = @import("std");

pub const Material = struct {
    super: Base = undefined,

    normal_map: Texture = undefined,

    color: Vec4f = undefined,

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: *Worker) Sample {
        const color = if (self.super.color_map.isValid()) ts.sample2D_3(self.super.color_map, rs.uv, worker.scene) else self.color;

        if (self.normal_map.isValid()) {
            const n = hlp.sampleNormal(wo, rs, self.normal_map, worker.scene);
            return Sample.initN(rs, n, wo, color, Vec4f.init1(0.0));
        }

        return Sample.init(rs, wo, color, Vec4f.init1(0.0));
    }
};
