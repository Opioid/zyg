const Base = @import("../material_base.zig").Base;
const Sample = @import("../sample.zig").Sample;
const Volumetric = @import("sample.zig").Sample;
const Null = @import("../null/sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Worker = @import("../../worker.zig").Worker;
const ts = @import("../../../image/texture/sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const fresnel = @import("../fresnel.zig");
const hlp = @import("../material_helper.zig");
const inthlp = @import("../../../rendering/integrator/helper.zig");
const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Material = struct {
    super: Base,

    pub fn init(sampler_key: ts.Key) Material {
        var super = Base.init(sampler_key, false);
        super.ior = 1.0;

        return .{ .super = super };
    }

    pub fn commit(self: *Material) void {
        _ = self;
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate) Sample {
        if (rs.subsurface) {
            const gs = self.super.vanDeHulstAnisotropy(rs.depth);
            return .{ .Volumetric = Volumetric.init(wo, rs, gs) };
        }

        return .{ .Null = Null.init(wo, rs) };
    }
};
