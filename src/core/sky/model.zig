const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const spectrum = base.spectrum;
const Spectrum = spectrum.DiscreteSpectralPowerDistribution(10, 380.0, 720.0);

const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("arpraguesky/ArPragueSkyModelGround.h");
});

pub const Model = struct {
    state: *c.ArPragueSkyModelGroundState,

    sun_direction: Vec4f,

    pub const Angular_radius = c.PSMG_SUN_RADIUS;

    const Zenith = Vec4f{ 0.0, 1.0, 0.0, 0.0 };
    const North = Vec4f{ 0.0, 0.0, 1.0, 0.0 };

    const Self = @This();

    pub fn init(alloc: *Allocator, sun_direction: Vec4f, visibility: f32) !Model {
        try Spectrum.staticInit(alloc);

        const elevation = std.math.acos(1.0 - math.saturate(-math.dot3(sun_direction, Zenith)));

        // const azimuth = std.math.max(math.dot3(sun_direction, North) * (2.0 * std.math.pi), 0.0);

        // const view_direction = [3]f64{ 0.0, 0.0, 1.0 };
        // const up_direction = [3]f64{ 0.0, 1.0, 0.0 };

        // var theta: f64 = undefined;
        // var gamma: f64 = undefined;
        // var shadow: f64 = undefined;

        // c.arpragueskymodelground_compute_angles(
        //     @floatCast(f64, elevation),
        //     @floatCast(f64, azimuth),
        //     &view_direction,
        //     &up_direction,
        //     &theta,
        //     &gamma,
        //     &shadow,
        // );

        const state = c.arpragueskymodelground_state_alloc_init(
            "/home/beni/Downloads/SkyModelDataset.dat",
            @floatCast(f64, elevation),
            @floatCast(f64, visibility),
            0.2,
        );

        return Model{
            .state = state,
            .sun_direction = sun_direction,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn evaluateSky(self: Self, wi: Vec4f) Vec4f {
        const wi_dot_z = std.math.max(wi[1], 0.0000);
        const wi_dot_s = std.math.min(-math.dot3(wi, self.sun_direction), 1.0);

        const theta = std.math.acos(wi_dot_z);
        const gamma = std.math.acos(wi_dot_s);

        // Zenith angle (theta)

        // const double cosTheta = view_direction[0] * up_direction[0] + view_direction[1] * up_direction[1] + view_direction[2] * up_direction[2];
        // *theta = acos(cosTheta);

        // // Sun angle (gamma)

        // const double sun_direction[] = {cos(sun_azimuth) * cos(sun_elevation), sin(sun_azimuth) * cos(sun_elevation), sin(sun_elevation)};
        // const double cosGamma = view_direction[0] * sun_direction[0] + view_direction[1] * sun_direction[1] + view_direction[2] * sun_direction[2];
        // *gamma = acos(cosGamma);

        //   std.debug.print("{} {}\n", .{ gamma, theta });

        // double arpragueskymodelground_sky_radiance(
        // 	const ArPragueSkyModelGroundState  * state,
        // 	const double                   theta,
        // 	const double                   gamma,
        // 	const double                   shadow,
        // 	const double                   wavelength
        // 	);

        // {
        //     const elevation = std.math.max(math.dot3(self.sun_direction, Zenith) * (-0.5 * std.math.pi), 0.0);
        //     const azimuth = std.math.max(math.dot3(self.sun_direction, North) * (-2.0 * std.math.pi), 0.0);

        //     const view_direction = [3]f64{ @as(f64, wi[0]), @as(f64, wi[1]), @as(f64, wi[2]) };
        //     const up_direction = [3]f64{ 0.0, 1.0, 0.0 };

        //     var their_theta: f64 = undefined;
        //     var their_gamma: f64 = undefined;
        //     var shadow: f64 = undefined;

        //     c.arpragueskymodelground_compute_angles(
        //         @floatCast(f64, elevation),
        //         @floatCast(f64, azimuth),
        //         &view_direction,
        //         &up_direction,
        //         &their_theta,
        //         &their_gamma,
        //         &shadow,
        //     );

        //     std.debug.print("ours: {} {}; theirs: {} {}\n", .{ gamma, theta, their_gamma, their_theta });
        // }

        var radiance: Spectrum = undefined;

        for (radiance.values) |*bin, i| {
            const rwl = @floatCast(f32, c.arpragueskymodelground_sky_radiance(
                self.state,
                @floatCast(f64, theta),
                @floatCast(f64, gamma),
                0.0,
                Spectrum.wavelengthCenter(i),
            ));

            bin.* = rwl;
        }

        return @maximum(spectrum.XYZtoAP1(radiance.XYZ()), @splat(4, @as(f32, 0.0)));
    }

    pub fn evaluateSkyAndSun(self: Self, wi: Vec4f) Vec4f {
        const wi_dot_z = std.math.max(wi[1], 0.0000);
        const theta = std.math.acos(wi_dot_z);

        var radiance: Spectrum = undefined;

        for (radiance.values) |*bin, i| {
            const rwl = @floatCast(f32, c.arpragueskymodelground_solar_radiance(
                self.state,
                @floatCast(f64, theta),
                Spectrum.wavelengthCenter(i),
            ));

            bin.* = rwl;
        }

        return @maximum(spectrum.XYZtoAP1(radiance.XYZ()), @splat(4, @as(f32, 0.0)));
    }

    pub fn turbidityToVisibility(turbidity: f32) f32 {
        return 7487.0 * @exp(-3.41 * turbidity) + 117.1 * @exp(-0.4768 * turbidity);
    }
};
