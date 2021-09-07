const Null = @import("../../resource/cache.zig").Null;

pub const Texture = struct {
    pub const Type = enum {
        Invalid,
        Byte3_sRGB,
    };

    type: Type = Type.Invalid,
    image: u32 = Null,
};
