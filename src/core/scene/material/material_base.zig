const Texture = @import("../../image/texture/texture.zig").Texture;
const ts = @import("../../image/texture/sampler.zig");
const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Flags = base.flags.Flags;

pub const Base = struct {
    pub const RadianceSample = struct {
        uvw: Vec4f,

        pub fn init2(uv: Vec2f, pdf_: f32) RadianceSample {
            return .{ .uvw = .{ uv[0], uv[1], 0.0, pdf_ } };
        }

        pub fn init3(uvw: Vec4f, pdf_: f32) RadianceSample {
            return .{ .uvw = .{ uvw[0], uvw[1], uvw[2], pdf_ } };
        }

        pub fn pdf(self: RadianceSample) f32 {
            return self.uvw[3];
        }
    };

    pub const Property = enum(u32) {
        None = 0,
        TwoSided = 1 << 0,
        EmissionMap = 1 << 1,
    };

    properties: Flags(Property),

    sampler_key: ts.Key,

    mask: Texture = undefined,
    color_map: Texture = undefined,

    emission: Vec4f = undefined,

    ior: f32 = undefined,

    pub fn init(sampler_key: ts.Key, two_sided: bool) Base {
        return .{
            .properties = Flags(Property).init1(if (two_sided) .TwoSided else .None),
            .sampler_key = sampler_key,
        };
    }
};
