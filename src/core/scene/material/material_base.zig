const Texture = @import("../../image/texture/texture.zig").Texture;
const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const Flags = base.flags.Flags;

pub const Base = struct {
    pub const Property = enum(u32) {
        None = 0,
        Two_sided = 1 << 0,
        Emission_map = 1 << 1,
    };

    properties: Flags(Property),

    mask: Texture = undefined,
    color_map: Texture = undefined,

    emission: Vec4f = undefined,

    pub fn init(two_sided: bool) Base {
        return .{ .properties = Flags(Property).init1(if (two_sided) .Two_sided else .None) };
    }
};
