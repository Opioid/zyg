const Base = @import("../material_base.zig").Base;
const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Material = struct {
    super: Base = undefined,

    const color_front = Vec4f.init3(0.4, 0.9, 0.1);
    const color_back = Vec4f.init3(0.9, 0.1, 0.4);

    pub fn sample(wo: Vec4f, rs: Renderstate) Sample {
        const n = rs.t.cross3(rs.b);

        const same_side = n.dot3(rs.n) > 0.0;

        const color = if (same_side) color_front else color_back;

        return Sample.init(rs, wo, color);
    }
};
