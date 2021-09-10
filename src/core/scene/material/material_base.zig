const Texture = @import("../../image/texture/texture.zig").Texture;
const Flags = @import("base").flags.Flags;

pub const Base = struct {
    pub const Properties = enum {
        None,
        Two_sided,
    };

    properties: Flags(Properties),

    color_map: Texture = undefined,

    pub fn init(two_sided: bool) Base {
        return .{ .properties = Flags(Properties).init1(if (two_sided) .Two_sided else .None) };
    }
};
