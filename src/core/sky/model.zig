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

    sun_direction: Vec4f,
    shadow_direction: Vec4f,

    pub const Angular_radius = c.PSMG_SUN_RADIUS;

    const Self = @This();

    pub fn init(alloc: Allocator, sun_direction: Vec4f, visibility: f32, albedo: f32, fs: *Filesystem) !Model {
        Spectrum.staticInit();

        var stream = try fs.readStream(alloc, "sky/SkyModelDataset.dat.gz");
        defer stream.deinit();

        const sun_elevation = -std.math.asin(sun_direction[1]);

        const state = c.arpragueskymodelground_state_alloc_init_handle(
            &stream,
            readStream,
            sun_elevation,
            visibility,
            albedo,
        ) orelse return Error.FailedToLoadSky;

        const d = @sqrt(sun_direction[0] * sun_direction[0] + sun_direction[2] * sun_direction[2]);

        const shadow_direction = Vec4f{
            (-sun_direction[0] / d) * sun_direction[1],
            @sqrt(1.0 - sun_direction[1] * sun_direction[1]),
            (-sun_direction[2] / d) * sun_direction[1],
            0.0,
        };

        return Model{
            .state = state,
            .sun_direction = sun_direction,
            .shadow_direction = shadow_direction,
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
        const wi_dot_z = std.math.clamp(wi[1], -1.0, 1.0);
        const theta = std.math.acos(wi_dot_z);

        const cos_gamma = std.math.clamp(-math.dot3(wi, self.sun_direction), -1.0, 1.0);
        const gamma = std.math.acos(cos_gamma);

        const cos_shadow = std.math.clamp(math.dot3(wi, self.shadow_direction), -1.0, 1.0);
        const shadow = std.math.acos(cos_shadow);

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
                )) / @floatFromInt(f32, samples.len);
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
                )) / @floatFromInt(f32, samples.len);
            }

            bin.* = rwl;
        }

        return spectrum.XYZtoAP1(radiance.XYZ());
    }

    pub fn turbidityToVisibility(turbidity: f32) f32 {
        return 7487.0 * @exp(-3.41 * turbidity) + 117.1 * @exp(-0.4768 * turbidity);
    }
};
