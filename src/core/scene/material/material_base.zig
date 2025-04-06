const Rainbow = @import("rainbow_integral.zig");
const fresnel = @import("fresnel.zig");
const Renderstate = @import("../renderstate.zig").Renderstate;
const Worker = @import("../../rendering/worker.zig").Worker;
const Texture = @import("../../image/texture/texture.zig").Texture;
const ts = @import("../../image/texture/texture_sampler.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Base = struct {
    pub const RadianceResult = struct {
        emission: Vec4f,
        num_samples: u32,
    };

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
        color_map: bool = false,
        emission_image_map: bool = false,
        scattering_volume: bool = false,
        dense_sss_optimization: bool = false,
    };

    properties: Properties = .{},

    sampler_key: ts.Key = .{},

    mask: Texture = Texture.initUniform1(1.0),

    priority: i8 = 0,

    pub fn setTwoSided(self: *Base, two_sided: bool) void {
        self.properties.two_sided = two_sided;
    }

    pub fn opacity(self: *const Base, rs: Renderstate, sampler: *Sampler, worker: *const Worker) f32 {
        return ts.sample2D_1(self.sampler_key, self.mask, rs, sampler, worker);
    }

    pub const Start_wavelength = Rainbow.Wavelength_start;
    pub const End_wavelength = Rainbow.Wavelength_end;

    pub fn spectrumAtWavelength(lambda: f32, value: f32) Vec4f {
        const start = Rainbow.Wavelength_start;
        const end = Rainbow.Wavelength_end;
        const nb: f32 = @floatFromInt(Rainbow.Num_bands);

        const u = ((lambda - start) / (end - start)) * nb;
        const id: u32 = @intFromFloat(u);
        const frac = u - @as(f32, @floatFromInt(id));

        if (id >= Rainbow.Num_bands - 1) {
            return Rainbow.Rainbow[Rainbow.Num_bands - 1];
        }

        return @as(Vec4f, @splat(value)) * math.lerp(Rainbow.Rainbow[id], Rainbow.Rainbow[id + 1], @as(Vec4f, @splat(frac)));
    }
};
