const Base = @import("../sample_base.zig").SampleBase;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const base = @import("base");
usingnamespace base.math;

pub const Sample = struct {
    super: Base,

    pub fn init(rs: Renderstate, wo: Vec4f, radiance: Vec4f) Sample {
        return .{ .super = Base.init(rs, wo, radiance, radiance) };
    }
};
