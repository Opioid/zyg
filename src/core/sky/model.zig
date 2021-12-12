const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const spectrum = base.spectrum;
const Spectrum = spectrum.DiscreteSpectralPowerDistribution(34, 380.0, 720.0);

const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("arpraguesky/ArPragueSkyModelGround.h");
});

pub const Model = struct {
    state: *c.ArPragueSkyModelGroundState,

    sun_elevation: f32,
    sun_azimuth: f32,

    pub const Angular_radius = c.PSMG_SUN_RADIUS;

    const Self = @This();

    pub fn init(alloc: Allocator, sun_direction: Vec4f, visibility: f32) !Model {
        try Spectrum.staticInit(alloc);

        const sun_elevation = elevation(sun_direction);
        const sun_azimuth = azimuth(sun_direction);

        const state = c.arpragueskymodelground_state_alloc_init(
            "/home/beni/Downloads/SkyModelDataset.dat",
            sun_elevation,
            visibility,
            0.2,
        );

        return Model{
            .state = state,
            .sun_elevation = sun_elevation,
            .sun_azimuth = sun_azimuth,
        };
    }

    pub fn deinit(self: *Self) void {
        c.arpragueskymodelground_state_free(self.state);
    }

    pub fn evaluateSky(self: Self, wi: Vec4f) Vec4f {
        const vd = [3]f64{ @floatCast(f64, wi[0]), @floatCast(f64, wi[2]), @floatCast(f64, wi[1]) };
        const ud = [3]f64{ 0.0, 0.0, 1.0 };

        var theta: f64 = undefined;
        var gamma: f64 = undefined;
        var shadow: f64 = undefined;

        c.arpragueskymodelground_compute_angles(
            self.sun_elevation,
            self.sun_azimuth,
            &vd,
            &ud,
            &theta,
            &gamma,
            &shadow,
        );

        var radiance: Spectrum = undefined;

        for (radiance.values) |*bin, i| {
            const rwl = @floatCast(f32, c.arpragueskymodelground_sky_radiance(
                self.state,
                theta,
                gamma,
                shadow,
                Spectrum.wavelengthCenter(i),
            ));

            bin.* = rwl;
        }

        return spectrum.XYZtoAP1(radiance.XYZ());
    }

    pub fn evaluateSkyAndSun(self: Self, wi: Vec4f) Vec4f {
        const wi_dot_z = std.math.clamp(wi[1], -1.0, 1.0);
        const theta = std.math.acos(wi_dot_z);

        var radiance: Spectrum = undefined;

        for (radiance.values) |*bin, i| {
            const rwl = @floatCast(f32, c.arpragueskymodelground_solar_radiance(
                self.state,
                theta,
                Spectrum.wavelengthCenter(i),
            ));

            bin.* = rwl;
        }

        return spectrum.XYZtoAP1(radiance.XYZ());
    }

    pub fn turbidityToVisibility(turbidity: f32) f32 {
        return 7487.0 * @exp(-3.41 * turbidity) + 117.1 * @exp(-0.4768 * turbidity);
    }

    fn elevation(dir: Vec4f) f32 {
        const dir_dot_z = -dir[1];
        return (std.math.pi / 2.0) - std.math.acos(dir_dot_z);
    }

    fn azimuth(dir: Vec4f) f32 {
        return -std.math.atan2(f32, -dir[0], -dir[2]) + 0.5 * std.math.pi;
    }
};
