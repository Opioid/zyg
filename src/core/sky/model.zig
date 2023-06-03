const Filesystem = @import("../file/system.zig").System;
const ReadStream = @import("../file/read_stream.zig").ReadStream;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const spectrum = base.spectrum;
const Spectrum = spectrum.DiscreteSpectralPowerDistribution(10, 380.0, 740.0);
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("arpraguesky/ArPragueSkyModelGround.h");
});

const Error = error{
    FailedToLoadSky,
};

pub const Model = struct {
    state: *c.ArPragueSkyModelGroundState,

    sun_elevation: f32,
    sun_azimuth: f32,

    pub const Angular_radius = c.PSMG_SUN_RADIUS;

    const Self = @This();

    pub fn init(alloc: Allocator, sun_direction: Vec4f, visibility: f32, albedo: f32, fs: *Filesystem) !Model {
        Spectrum.staticInit();

        var stream = try fs.readStream(alloc, "sky/SkyModelDataset.dat.gz");
        defer stream.deinit();

        const sun_elevation = elevation(sun_direction);
        const sun_azimuth = azimuth(sun_direction);

        const state = c.arpragueskymodelground_state_alloc_init_handle(
            &stream,
            readStream,
            sun_elevation,
            visibility,
            albedo,
        ) orelse return Error.FailedToLoadSky;

        return Model{
            .state = state,
            .sun_elevation = sun_elevation,
            .sun_azimuth = sun_azimuth,
        };
    }

    fn readStream(buffer: ?*anyopaque, size: usize, count: usize, stream: ?*c.FILE) callconv(.C) usize {
        if (null == buffer or null == stream) {
            return 0;
        }

        var stream_ptr = @ptrCast(*ReadStream, @alignCast(@alignOf(ReadStream), stream));
        var dest = @ptrCast([*]u8, buffer)[0 .. size * count];
        return (stream_ptr.read(dest) catch 0) / size;
    }

    pub fn deinit(self: *Self) void {
        c.arpragueskymodelground_state_free(self.state);
    }

    pub fn evaluateSky(self: Self, wi: Vec4f, rng: *RNG) Vec4f {
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

        var samples: [16]f32 = undefined;

        var radiance: Spectrum = undefined;

        for (&radiance.values, 0..) |*bin, i| {
            math.goldenRatio1D(&samples, rng.randomFloat());

            var rwl: f32 = 0.0;

            for (samples) |s| {
                rwl += @floatCast(f32, c.arpragueskymodelground_sky_radiance(
                    self.state,
                    theta,
                    gamma,
                    shadow,
                    Spectrum.randomWavelength(i, s),
                )) / @intToFloat(f32, samples.len);
            }

            bin.* = rwl;
        }

        return spectrum.XYZtoAP1(radiance.XYZ());
    }

    pub fn evaluateSkyAndSun(self: Self, wi: Vec4f, rng: *RNG) Vec4f {
        const wi_dot_z = std.math.clamp(wi[1], -1.0, 1.0);
        const theta = std.math.acos(wi_dot_z);

        var samples: [16]f32 = undefined;

        var radiance: Spectrum = undefined;

        for (&radiance.values, 0..) |*bin, i| {
            math.goldenRatio1D(&samples, rng.randomFloat());

            var rwl: f32 = 0.0;

            for (samples) |s| {
                rwl += @floatCast(f32, c.arpragueskymodelground_solar_radiance(
                    self.state,
                    theta,
                    Spectrum.randomWavelength(i, s),
                )) / @intToFloat(f32, samples.len);
            }

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
