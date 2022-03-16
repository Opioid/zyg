const Texture = @import("../../image/texture/texture.zig").Texture;
const Scene = @import("../scene.zig").Scene;
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
    pub fn MappedValue(comptime Value: type) type {
        return struct {
            texture: Texture = .{},

            value: Value,

            const Self = @This();

            pub fn init(value: Value) Self {
                return .{ .value = value };
            }
        };
    }

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

    properties: Flags(Property) = .{},

    sampler_key: ts.Key = .{},

    mask: Texture = .{},
    color_map: Texture = .{},

    cc: CC = undefined,

    emission: Vec4f = @splat(4, @as(f32, 0.0)),

    ior: f32 = 1.5,
    attenuation_distance: f32 = 0.0,
    volumetric_anisotropy: f32 = 0.0,

    pub fn setTwoSided(self: *Base, two_sided: bool) void {
        self.properties.set(.TwoSided, two_sided);
    }

    pub fn setVolumetric(
        self: *Base,
        attenuation_color: Vec4f,
        subsurface_color: Vec4f,
        distance: f32,
        anisotropy: f32,
    ) void {
        const aniso = std.math.clamp(anisotropy, -0.999, 0.999);
        const cc = ccoef.attenuation(attenuation_color, subsurface_color, distance, aniso);

        self.cc = cc;
        self.attenuation_distance = distance;
        self.volumetric_anisotropy = aniso;
        self.properties.set(.ScatteringVolume, math.anyGreaterZero3(cc.s));
    }

    pub fn opacity(self: Base, uv: Vec2f, filter: ?ts.Filter, scene: Scene) f32 {
        const mask = self.mask;
        if (mask.valid()) {
            const key = ts.resolveKey(self.sampler_key, filter);
            return ts.sample2D_1(key, mask, uv, scene);
        }

        return 1.0;
    }

    pub fn border(self: Base, wi: Vec4f, n: Vec4f) f32 {
        const f0 = fresnel.Schlick.F0(self.ior, 1.0);
        const n_dot_wi = std.math.max(math.dot3(n, wi), 0.0);
        return 1.0 - fresnel.schlick1(n_dot_wi, f0);
    }

    pub fn similarityRelationScale(self: Base, depth: u32) f32 {
        const gs = self.vanDeHulstAnisotropy(depth);
        return vanDeHulst(self.volumetric_anisotropy, gs);
    }

    pub fn vanDeHulstAnisotropy(self: Base, depth: u32) f32 {
        if (depth < SR_low) {
            return self.volumetric_anisotropy;
        }

        if (depth < SR_high) {
            const towards_zero = SR_inv_range * @intToFloat(f32, depth - SR_low);
            return math.lerp(self.volumetric_anisotropy, 0.0, towards_zero);
        }

        return 0.0;
    }

    fn vanDeHulst(g: f32, gs: f32) f32 {
        return (1.0 - g) / (1.0 - gs);
    }

    const Num_bands = 36;

    // For now this is just copied from the table calculated with sprout
    const Rainbow = [Num_bands + 1]Vec4f{
        .{ 0.00962823, 0, 0.100005, 1.0 },
        .{ 0.025591, 0, 0.270464, 1.0 },
        .{ 0.0620753, 0, 0.674678, 1.0 },
        .{ 0.108291, 0, 1, 1.0 },
        .{ 0.126475, 0, 1, 1.0 },
        .{ 0.114185, 0, 1, 1.0 },
        .{ 0.0822336, 0, 1, 1.0 },
        .{ 0.0363506, 0, 1, 1.0 },
        .{ 0, 0.0492168, 1, 1.0 },
        .{ 0, 0.15781, 0.797668, 1.0 },
        .{ 0, 0.274093, 0.50495, 1.0 },
        .{ 0, 0.417446, 0.318206, 1.0 },
        .{ 0, 0.614652, 0.206342, 1.0 },
        .{ 0, 0.855357, 0.124255, 1.0 },
        .{ 0, 1, 0.0685739, 1.0 },
        .{ 0, 1, 0.0401956, 1.0 },
        .{ 0.108656, 1, 0.0223897, 1.0 },
        .{ 0.25955, 1, 0.0117566, 1.0 },
        .{ 0.435642, 1, 0.00684643, 1.0 },
        .{ 0.633237, 1, 0.00536615, 1.0 },
        .{ 0.840695, 0.976963, 0.00562624, 1.0 },
        .{ 1, 0.788856, 0.00667743, 1.0 },
        .{ 1, 0.584584, 0.00753228, 1.0 },
        .{ 1, 0.390579, 0.00812561, 1.0 },
        .{ 1, 0.230459, 0.00812094, 1.0 },
        .{ 1, 0.115009, 0.00748867, 1.0 },
        .{ 1, 0.0434112, 0.00650762, 1.0 },
        .{ 0.859776, 0.00545805, 0.00514384, 1.0 },
        .{ 0.646021, 0, 0.00386653, 1.0 },
        .{ 0.456052, 0, 0.00273025, 1.0 },
        .{ 0.301629, 0, 0.00180471, 1.0 },
        .{ 0.187707, 0, 0.00112459, 1.0 },
        .{ 0.110306, 0, 0.000661374, 1.0 },
        .{ 0.0652361, 0, 0.000391372, 1.0 },
        .{ 0.0365208, 0, 0.000219199, 1.0 },
        .{ 0.0200153, 0, 0.000120156, 1.0 },
        .{ 0.0200153, 0, 0.000120156, 1.0 },
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

    var SR_low: u32 = 16;
    var SR_high: u32 = 64;
    var SR_inv_range: f32 = 1.0 / @intToFloat(f32, 64 - 16);

    pub fn setSimilarityRelationRange(low: u32, high: u32) void {
        SR_low = low;
        SR_high = high;
        SR_inv_range = 1.0 / @intToFloat(f32, high - low);
    }
};
