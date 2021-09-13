const Base = @import("../material_base.zig").Base;
const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Material = struct {
    super: Base = undefined,

    thickness: f32 = undefined,

    pub fn commit(self: *Material) void {
        self.super.properties.set(.Two_sided, if (self.thickness > 0.0) true else false);
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate) Sample {
        _ = self;
        return Sample.init(rs, wo);
    }
};
