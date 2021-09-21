const Texture = @import("../../image/texture/texture.zig").Texture;
const ts = @import("../../image/texture/sampler.zig");
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

    sampler_key: ts.Key,

    mask: Texture = undefined,
    color_map: Texture = undefined,

    emission: Vec4f = undefined,

    ior: f32 = undefined,

    pub fn init(sampler_key: ts.Key, two_sided: bool) Base {
        return .{
            .properties = Flags(Property).init1(if (two_sided) .Two_sided else .None),
            .sampler_key = sampler_key,
        };
    }
};
