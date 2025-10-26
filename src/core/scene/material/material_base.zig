const Rainbow = @import("rainbow_integral.zig");
const fresnel = @import("fresnel.zig");
const Scene = @import("../scene.zig").Scene;
const Texture = @import("../../texture/texture.zig").Texture;
const ts = @import("../../texture/texture_sampler.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Base = struct {
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

    priority: i8 = 0,

    mask: Texture = Texture.initUniform1(1.0),

    pub fn setTwoSided(self: *Base, two_sided: bool) void {
        self.properties.two_sided = two_sided;
    }

    pub fn opacity(self: *const Base, uv: Vec2f, sampler: *Sampler, scene: *const Scene) f32 {
        if (!self.mask.isImage()) {
            return 1.0;
        }

        return ts.sampleImage2D_1(self.mask, uv, sampler.sample1D(), scene);
    }

    pub fn stochasticOpacity(self: *const Base, uv: Vec2f, sampler: *Sampler, scene: *const Scene) bool {
        if (!self.mask.isImage()) {
            return true;
        }

        const o = ts.sampleImage2D_1(self.mask, uv, sampler.sample1D(), scene);
        if (0.0 == o or (o < 1.0 and o <= sampler.sample1D())) {
            return false;
        }

        return true;
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
