const Texture = @import("../../image/texture/texture.zig").Texture;
const Flags = @import("base").flags.Flags;

pub const Base = struct {
    pub const Property = enum(u32) {
        None = 0,
        Two_sided = 1 << 0,
    };

    properties: Flags(Property),

    mask: Texture = undefined,
    color_map: Texture = undefined,

    pub fn init(two_sided: bool) Base {
        return .{ .properties = Flags(Property).init1(if (two_sided) .Two_sided else .None) };
    }
};
