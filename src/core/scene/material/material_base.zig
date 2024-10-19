const Rainbow = @import("rainbow_integral.zig");
const ccoef = @import("collision_coefficients.zig");
const CC = ccoef.CC;
const fresnel = @import("fresnel.zig");
const Emittance = @import("../light/emittance.zig").Emittance;
const Scene = @import("../scene.zig").Scene;
const Texture = @import("../../image/texture/texture.zig").Texture;
const ts = @import("../../image/texture/texture_sampler.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

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

    pub const Properties = packed struct {
        two_sided: bool = false,
        evaluate_visibility: bool = false,
        caustic: bool = false,
        emissive: bool = false,
        emission_map: bool = false,
        scattering_volume: bool = false,
        dense_sss_optimization: bool = false,
    };

    properties: Properties = .{},

    sampler_key: ts.Key = .{},

    mask: Texture = .{},
    color_map: Texture = .{},

    cc: CC = undefined,

    emittance: Emittance = .{},

    priority: i8 = 0,
    ior: f32 = 1.5,
    attenuation_distance: f32 = 0.0,
    volumetric_anisotropy: f32 = 0.0,

    pub fn setTwoSided(self: *Base, two_sided: bool) void {
        self.properties.two_sided = two_sided;
    }

    pub fn setVolumetric(
        self: *Base,
        attenuation_color: Vec4f,
        subsurface_color: Vec4f,
        distance: f32,
        anisotropy: f32,
    ) void {
        const aniso = math.clamp(anisotropy, -0.999, 0.999);
        const cc = ccoef.attenuation(attenuation_color, subsurface_color, distance, aniso);

        self.cc = cc;
        self.attenuation_distance = distance;
        self.volumetric_anisotropy = aniso;
        self.properties.scattering_volume = math.anyGreaterZero3(cc.s);
    }

    pub fn opacity(self: *const Base, uv: Vec2f, sampler: *Sampler, scene: *const Scene) f32 {
        const mask = self.mask;
        if (mask.valid()) {
            return ts.sample2D_1(self.sampler_key, mask, uv, sampler, scene);
        }

        return 1.0;
    }

    pub fn similarityRelationScale(self: *const Base, depth: u32) f32 {
        const gs = self.vanDeHulstAnisotropy(depth);
        return vanDeHulst(self.volumetric_anisotropy, gs);
    }

    pub fn vanDeHulstAnisotropy(self: *const Base, depth: u32) f32 {
        if (depth < SR_low) {
            return self.volumetric_anisotropy;
        }

        if (depth < SR_high) {
            const towards_zero = SR_inv_range * @as(f32, @floatFromInt(depth - SR_low));
            return math.lerp(self.volumetric_anisotropy, 0.0, towards_zero);
        }

        return 0.0;
    }

    fn vanDeHulst(g: f32, gs: f32) f32 {
        return (1.0 - g) / (1.0 - gs);
    }

    pub const Start_wavelength = Rainbow.Wavelength_start;
    pub const End_wavelength = Rainbow.Wavelength_end;

    pub fn spectrumAtWavelength(lambda: f32, value: f32) Vec4f {
        const start = Rainbow.Wavelength_start;
        const end = Rainbow.Wavelength_end;
        const nb = @as(f32, @floatFromInt(Rainbow.Num_bands));

        const u = ((lambda - start) / (end - start)) * nb;
        const id = @as(u32, @intFromFloat(u));
        const frac = u - @as(f32, @floatFromInt(id));

        if (id >= Rainbow.Num_bands - 1) {
            return Rainbow.Rainbow[Rainbow.Num_bands - 1];
        }

        return @as(Vec4f, @splat(value)) * math.lerp(Rainbow.Rainbow[id], Rainbow.Rainbow[id + 1], @as(Vec4f, @splat(frac)));
    }

    var SR_low: u32 = 16;
    var SR_high: u32 = 64;
    var SR_inv_range: f32 = 1.0 / @as(f32, @floatFromInt(64 - 16));

    pub fn setSimilarityRelationRange(low: u32, high: u32) void {
        SR_low = low;
        SR_high = high;
        SR_inv_range = 1.0 / @as(f32, @floatFromInt(high - low));
    }
};
