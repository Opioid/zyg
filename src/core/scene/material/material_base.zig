const Texture = @import("../../image/texture/texture.zig").Texture;
const Worker = @import("../worker.zig").Worker;
const ts = @import("../../image/texture/sampler.zig");
const ccoef = @import("collision_coefficients.zig");
const CC = ccoef.CC;
const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Flags = base.flags.Flags;

const std = @import("std");

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
        ScatteringVolume = 1 << 2,
        HeterogeneousVolume = 1 << 3,
    };

    properties: Flags(Property),

    sampler_key: ts.Key,

    mask: Texture = .{},
    color_map: Texture = .{},

    cc: CC = undefined,

    emission: Vec4f = undefined,

    ior: f32 = undefined,
    attenuation_distance: f32 = undefined,
    volumetric_anisotropy: f32 = undefined,

    pub fn init(sampler_key: ts.Key, two_sided: bool) Base {
        return .{
            .properties = Flags(Property).init1(if (two_sided) .TwoSided else .None),
            .sampler_key = sampler_key,
        };
    }

    pub fn setVolumetric(
        self: *Base,
        attenuation_color: Vec4f,
        subsurface_color: Vec4f,
        distance: f32,
        anisotropy: f32,
    ) void {
        const aniso = std.math.clamp(anisotropy, -0.999, 0.999);
        self.cc = ccoef.attenuation(attenuation_color, subsurface_color, distance, anisotropy);
        self.attenuation_distance = distance;
        self.volumetric_anisotropy = aniso;
    }

    pub fn opacity(self: Base, uv: Vec2f, filter: ?ts.Filter, worker: Worker) f32 {
        const mask = self.mask;
        if (mask.isValid()) {
            const key = ts.resolveKey(self.sampler_key, filter);
            return ts.sample2D_1(key, mask, uv, worker.scene.*);
        }

        return 1.0;
    }

    pub fn vanDeHulstAnisotropy(self: Base, depth: u32) f32 {
        _ = depth;
        return self.volumetric_anisotropy;
    }
};
