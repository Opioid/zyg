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
    emission_map: Texture = undefined,

    color: Vec4f = undefined,

    emission_factor: f32 = undefined,

    pub fn init(sampler_key: ts.Key, two_sided: bool) Material {
        return .{ .super = Base.init(sampler_key, two_sided) };
    }

    pub fn commit(self: *Material) void {
        self.super.properties.set(.Emission_map, self.emission_map.isValid());
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: *Worker) Sample {
        const key = ts.resolveKey(self.super.sampler_key, rs.filter);

        const color = if (self.super.color_map.isValid()) ts.sample2D_3(
            key,
            self.super.color_map,
            rs.uv,
            worker.scene,
        ) else self.color;

        const ef = @splat(4, self.emission_factor);
        const radiance = if (self.emission_map.isValid()) ef * ts.sample2D_3(
            key,
            self.emission_map,
            rs.uv,
            worker.scene,
        ) else ef * self.super.emission;

        if (self.normal_map.isValid()) {
            const n = hlp.sampleNormal(wo, rs, self.normal_map, key, worker.scene);
            return Sample.initN(rs, n, wo, color, radiance);
        }

        return Sample.init(rs, wo, color, radiance);
    }
};
