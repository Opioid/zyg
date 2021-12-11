const Interpolated = @import("interpolated.zig").Interpolated;
const math = @import("../math/math.zig");
const Vec4f = math.Vec4f;
const xyz = @import("../spectrum/xyz.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn DiscreteSpectralPowerDistribution(
    comptime N: comptime_int,
    comptime WL_start: f32,
    comptime WL_end: f32,
) type {
    return struct {
        values: [N]f32 = undefined,

        var Cie: [N]Vec4f = undefined;
        var Wavelengths: [N + 1]f32 = undefined;
        var Step: f32 = 0.0;

        const Self = @This();

        pub fn staticInit(alloc: Allocator) !void {
            if (Step > 0.0) {
                return;
            }

            const step = (WL_end - WL_start) / @intToFloat(f32, N);

            // initialize the wavelengths ranges of the bins
            for (Wavelengths) |*wl, i| {
                wl.* = WL_start + @intToFloat(f32, i) * step;
            }

            Step = step;

            var CIE_X = try Interpolated.init(alloc, &xyz.CIE_Wavelengths_360_830_1nm, &xyz.CIE_X_360_830_1nm);
            defer CIE_X.deinit(alloc);

            var CIE_Y = try Interpolated.init(alloc, &xyz.CIE_Wavelengths_360_830_1nm, &xyz.CIE_Y_360_830_1nm);
            defer CIE_Y.deinit(alloc);

            var CIE_Z = try Interpolated.init(alloc, &xyz.CIE_Wavelengths_360_830_1nm, &xyz.CIE_Z_360_830_1nm);
            defer CIE_Z.deinit(alloc);

            const cie_x = Self.initInterpolated(CIE_X);
            const cie_y = Self.initInterpolated(CIE_Y);
            const cie_z = Self.initInterpolated(CIE_Z);

            for (Cie) |*c, i| {
                c.* = Vec4f{ cie_x.values[i], cie_y.values[i], cie_z.values[i], 0.0 };
            }
        }

        pub fn wavelengthCenter(bin: usize) f32 {
            return (Wavelengths[bin] + Wavelengths[bin + 1]) * 0.5;
        }

        pub fn startWavelength() f32 {
            return Wavelengths[0];
        }

        pub fn endWavelength() f32 {
            return Wavelengths[N];
        }

        pub fn initInterpolated(interpolated: Interpolated) Self {
            var result = Self{};

            for (result.values) |*v, i| {
                const a = Wavelengths[i];
                const b = Wavelengths[i + 1];

                v.* = interpolated.integrate(a, b) / (b - a);
            }

            return result;
        }

        pub fn XYZ(self: Self) Vec4f {
            var tri = @splat(4, @as(f32, 0.0));
            for (self.values) |v, i| {
                tri += @splat(4, Step * v) * Cie[i];
            }

            return tri;
        }

        pub fn normalizedXYZ(self: Self) Vec4f {
            const Normalization: f32 = 1.0 / 106.856895;
            return @splat(4, Normalization) * self.XYZ();
        }
    };
}
