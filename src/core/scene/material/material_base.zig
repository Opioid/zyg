const Texture = @import("../../image/texture/texture.zig").Texture;
const Worker = @import("../worker.zig").Worker;
const ts = @import("../../image/texture/sampler.zig");
const ccoef = @import("collision_coefficients.zig");
const CC = ccoef.CC;
const fresnel = @import("fresnel.zig");
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
        Caustic = 1 << 1,
        EmissionMap = 1 << 2,
        ScatteringVolume = 1 << 3,
        HeterogeneousVolume = 1 << 4,
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
        const cc = ccoef.attenuation(attenuation_color, subsurface_color, distance, anisotropy);

        self.cc = cc;
        self.attenuation_distance = distance;
        self.volumetric_anisotropy = aniso;
        self.properties.set(.ScatteringVolume, math.anyGreaterZero3(self.cc.s));
    }

    pub fn opacity(self: Base, uv: Vec2f, filter: ?ts.Filter, worker: Worker) f32 {
        const mask = self.mask;
        if (mask.isValid()) {
            const key = ts.resolveKey(self.sampler_key, filter);
            return ts.sample2D_1(key, mask, uv, worker.scene.*);
        }

        return 1.0;
    }

    pub fn border(self: Base, wi: Vec4f, n: Vec4f) f32 {
        const f0 = fresnel.Schlick.F0(self.ior, 1.0);
        const n_dot_wi = std.math.max(math.dot3(n, wi), 0.0);
        return 1.0 - fresnel.schlick1(n_dot_wi, f0);
    }

    pub fn vanDeHulstAnisotropy(self: Base, depth: u32) f32 {
        _ = depth;
        return self.volumetric_anisotropy;
    }

    const Num_bands = 36;

    // For now this is just copied from the table calculated with sprout
    const Rainbow = [Num_bands + 1]Vec4f{
        .{ 0.00908, 0, 0.100005, 1.0 },
        .{ 0.0241339, 0, 0.270464, 1.0 },
        .{ 0.0585407, 0, 0.674678, 1.0 },
        .{ 0.102125, 0, 1, 1.0 },
        .{ 0.119274, 0, 1, 1.0 },
        .{ 0.107683, 0, 1, 1.0 },
        .{ 0.0775513, 0, 1, 1.0 },
        .{ 0.0342808, 0, 1, 1.0 },
        .{ 0, 0.0462888, 1, 1.0 },
        .{ 0, 0.148422, 0.797668, 1.0 },
        .{ 0, 0.257787, 0.50495, 1.0 },
        .{ 0, 0.392612, 0.318206, 1.0 },
        .{ 0, 0.578086, 0.206342, 1.0 },
        .{ 0, 0.804471, 0.124255, 1.0 },
        .{ 0, 1, 0.0685739, 1.0 },
        .{ 0, 1, 0.0401956, 1.0 },
        .{ 0.102469, 1, 0.0223897, 1.0 },
        .{ 0.244771, 1, 0.0117566, 1.0 },
        .{ 0.410837, 1, 0.00684643, 1.0 },
        .{ 0.59718, 1, 0.00536615, 1.0 },
        .{ 0.792826, 0.918842, 0.00562624, 1.0 },
        .{ 0.980582, 0.741926, 0.00667743, 1.0 },
        .{ 1, 0.549806, 0.00753228, 1.0 },
        .{ 1, 0.367343, 0.00812561, 1.0 },
        .{ 1, 0.216749, 0.00812094, 1.0 },
        .{ 1, 0.108167, 0.00748867, 1.0 },
        .{ 1, 0.0408286, 0.00650762, 1.0 },
        .{ 0.810821, 0.00513334, 0.00514384, 1.0 },
        .{ 0.609237, 0, 0.00386653, 1.0 },
        .{ 0.430085, 0, 0.00273025, 1.0 },
        .{ 0.284454, 0, 0.00180471, 1.0 },
        .{ 0.177019, 0, 0.00112459, 1.0 },
        .{ 0.104025, 0, 0.000661374, 1.0 },
        .{ 0.0615216, 0, 0.000391372, 1.0 },
        .{ 0.0344413, 0, 0.000219199, 1.0 },
        .{ 0.0188756, 0, 0.000120156, 1.0 },
        .{ 0.0188756, 0, 0.000120156, 1.0 },
    };

    pub const Start_wavelength: f32 = 400.0;
    pub const End_wavelength: f32 = 700.0;

    pub fn spectrumAtWavelength(lambda: f32, value: f32) Vec4f {
        const start: f32 = Start_wavelength;
        const end: f32 = End_wavelength;
        const nb = @intToFloat(f32, Num_bands);

        const u = ((lambda - start) / (end - start)) * nb;
        const id = @floatToInt(u32, u);
        const frac = u - @intToFloat(f32, id);

        if (id >= Num_bands) {
            return Rainbow[Num_bands];
        }

        return @splat(4, value) * math.lerp3(Rainbow[id], Rainbow[id + 1], frac);
    }
};
