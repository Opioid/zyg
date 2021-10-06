const Base = @import("../material_base.zig").Base;
const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Material = struct {
    super: Base,

    const color_front = Vec4f{ 0.4, 0.9, 0.1, 0.0 };
    const color_back = Vec4f{ 0.9, 0.1, 0.4, 0.0 };

    pub fn init() Material {
        var super = Base.init(.{}, true);
        super.mask = .{};
        super.color_map = .{};
        super.emission = @splat(4, @as(f32, 1.0));
        super.ior = 1.5;

        return .{ .super = super };
    }

    pub fn sample(wo: Vec4f, rs: Renderstate) Sample {
        const n = math.cross3(rs.t, rs.b);

        const same_side = math.dot3(n, rs.n) > 0.0;

        const color = if (same_side) color_front else color_back;

        var result = Sample.init(rs, wo, color);
        result.super.layer.setTangentFrame(rs.t, rs.b, rs.n);
        return result;
    }
};
