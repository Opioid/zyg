const base = @import("base");
const math = base.math;
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

    sun_direction: Vec4f,

    pub const Angular_radius = c.PSMG_SUN_RADIUS;

    const Self = @This();

    pub fn init(alloc: Allocator, sun_direction: Vec4f, visibility: f32) !Model {
        try Spectrum.staticInit(alloc);

        const elev = elevation(sun_direction);

        const state = c.arpragueskymodelground_state_alloc_init(
            "/home/beni/Downloads/SkyModelDataset.dat",
            elev,
            visibility,
            0.2,
        );

        return Model{
            .state = state,
            .sun_direction = sun_direction,
        };
    }

    pub fn deinit(self: *Self) void {
        c.arpragueskymodelground_state_free(self.state);
    }

    pub fn evaluateSky(self: Self, wi: Vec4f) Vec4f {
        const wi_dot_z = std.math.clamp(wi[1], -1.0, 1.0);
        const wi_dot_s = std.math.clamp(-math.dot3(wi, self.sun_direction), -1.0, 1.0);

        const theta = std.math.acos(wi_dot_z);
        const gamma = std.math.acos(wi_dot_s);

        var radiance: Spectrum = undefined;

        for (radiance.values) |*bin, i| {
            const rwl = @floatCast(f32, c.arpragueskymodelground_sky_radiance(
                self.state,
                theta,
                gamma,
                0.0,
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
        if (dir_dot_z >= 0.0) {
            return std.math.acos(1.0 - dir_dot_z);
        }

        return -std.math.acos(1.0 + dir_dot_z);
    }
};

// pub const Model = struct {
//     state: *c.ArPragueSkyModelGroundState,

//     sun_direction: Vec4f,

//     pub const Angular_radius = c.PSMG_SUN_RADIUS;

//     const Elevation = math.degreesToRadians(30.0);
//     const Azimuth = math.degreesToRadians(180.0);
//     const Visibility = 100.0;
//     const Albedo = 0.4;

//     const Self = @This();

//     pub fn init(alloc: *Allocator, sun_direction: Vec4f, visibility: f32) !Model {
//         _ = visibility;

//         try Spectrum.staticInit(alloc);

//         const state = c.arpragueskymodelground_state_alloc_init(
//             "/home/beni/Downloads/SkyModelDataset.dat",
//             Elevation,
//             Visibility,
//             Albedo,
//         );

//         return Model{
//             .state = state,
//             .sun_direction = sun_direction,
//         };
//     }

//     pub fn deinit(self: *Self) void {
//         c.arpragueskymodelground_state_free(self.state);
//     }

//     pub fn evaluateSky(self: Self, wi: Vec4f) Vec4f {

//         // const elev = elevation(self.sun_direction);
//         // const azim = 0.5 * std.math.pi; //std.math.atan2(f32, -self.sun_direction[0], self.sun_direction[2]) + 1.5 * std.math.pi;

//         // //     std.debug.print("{}\n", .{azim});

//         const vd = [3]f64{ @floatCast(f64, wi[0]), @floatCast(f64, wi[1]), @floatCast(f64, wi[2]) };
//         const ud = [3]f64{ 0.0, 1.0, 0.0 };

//         var theta: f64 = 0.0;
//         var gamma: f64 = 0.0;
//         var shadow: f64 = 0.0;

//         c.arpragueskymodelground_compute_angles(
//             Elevation,
//             Azimuth,
//             &vd,
//             &ud,
//             &theta,
//             &gamma,
//             &shadow,
//         );

//         // var radiance: Spectrum = undefined;

//         // for (radiance.values) |*bin, i| {
//         //     const rwl = @floatCast(f32, c.arpragueskymodelground_sky_radiance(
//         //         self.state,
//         //         theta,
//         //         gamma,
//         //         shadow,
//         //         Spectrum.wavelengthCenter(i),
//         //     ));

//         //     bin.* = rwl;
//         // }

//         // return spectrum.XYZtoAP1(radiance.XYZ());

//         const rwl = @floatCast(f32, c.arpragueskymodelground_sky_radiance(
//             self.state,
//             theta,
//             gamma,
//             shadow,
//             550.0,
//         ));

//         return @splat(4, rwl);
//     }

//     pub fn evaluateSkyAndSun(self: Self, wi: Vec4f) Vec4f {
//         const wi_dot_z = std.math.clamp(wi[1], -1.0, 1.0);
//         const theta = std.math.acos(wi_dot_z);

//         var radiance: Spectrum = undefined;

//         for (radiance.values) |*bin, i| {
//             const rwl = @floatCast(f32, c.arpragueskymodelground_solar_radiance(
//                 self.state,
//                 theta,
//                 Spectrum.wavelengthCenter(i),
//             ));

//             bin.* = rwl;
//         }

//         return spectrum.XYZtoAP1(radiance.XYZ());
//     }

//     pub fn turbidityToVisibility(turbidity: f32) f32 {
//         return 7487.0 * @exp(-3.41 * turbidity) + 117.1 * @exp(-0.4768 * turbidity);
//     }

//     fn elevation(dir: Vec4f) f32 {
//         const dir_dot_z = -dir[1];
//         if (dir_dot_z >= 0.0) {
//             return std.math.acos(1.0 - dir_dot_z);
//         }

//         return -std.math.acos(1.0 + dir_dot_z);
//     }
// };

// const c = @cImport({
//     @cInclude("arhoseksky/ArHosekSkyModel.h");
// });

// pub const Model = struct {
//     state: *c.ArHosekSkyModelState,

//     sun_direction: Vec4f,

//     pub const Angular_radius = math.degreesToRadians(0.5 * 0.5334);

//     const Zenith = Vec4f{ 0.0, 1.0, 0.0, 0.0 };
//     const North = Vec4f{ 0.0, 0.0, 1.0, 0.0 };

//     const Self = @This();

//     pub fn init(alloc: *Allocator, sun_direction: Vec4f, visibility: f32) !Model {
//         _ = visibility;

//         try Spectrum.staticInit(alloc);

//         const elevation = std.math.acos(1.0 - math.saturate(-math.dot3(sun_direction, Zenith)));

//         const state = c.arhosekskymodelstate_alloc_init(
//             @floatCast(f64, elevation),
//             2.0,
//             0.2,
//         );

//         return Model{
//             .state = state,
//             .sun_direction = sun_direction,
//         };
//     }

//     pub fn deinit(self: *Self) void {
//         _ = self;
//     }

//     pub fn evaluateSky(self: Self, wi: Vec4f) Vec4f {
//         const wi_dot_z = std.math.max(wi[1], 0.0000);
//         const wi_dot_s = std.math.min(-math.dot3(wi, self.sun_direction), 1.0);

//         const theta = std.math.acos(wi_dot_z);
//         const gamma = std.math.acos(wi_dot_s);

//         var radiance: Spectrum = undefined;

//         for (radiance.values) |*bin, i| {
//             const rwl = @floatCast(f32, c.arhosekskymodel_radiance(
//                 self.state,
//                 theta,
//                 gamma,
//                 Spectrum.wavelengthCenter(i),
//             ));

//             bin.* = rwl;
//         }

//         return spectrum.XYZtoAP1(radiance.XYZ());
//     }

//     pub fn evaluateSkyAndSun(self: Self, wi: Vec4f) Vec4f {
//         const wi_dot_z = std.math.max(wi[1], 0.0000);
//         const wi_dot_s = std.math.min(-math.dot3(wi, self.sun_direction), 1.0);

//         const theta = std.math.acos(wi_dot_z);
//         const gamma = std.math.acos(wi_dot_s);

//         var radiance: Spectrum = undefined;

//         for (radiance.values) |*bin, i| {
//             const rwl = @floatCast(f32, c.arhosekskymodel_solar_radiance(
//                 self.state,
//                 theta,
//                 gamma,
//                 Spectrum.wavelengthCenter(i),
//             ));

//             bin.* = rwl;
//         }

//         return spectrum.XYZtoAP1(radiance.XYZ());
//     }

//     pub fn turbidityToVisibility(turbidity: f32) f32 {
//         return 7487.0 * @exp(-3.41 * turbidity) + 117.1 * @exp(-0.4768 * turbidity);
//     }
// };
