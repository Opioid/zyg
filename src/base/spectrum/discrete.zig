const Interpolated = @import("interpolated.zig").Interpolated;
const math = @import("../math/math.zig");
const Vec4f = math.Vec4f;
const xyz = @import("../spectrum/xyz.zig");

pub fn DiscreteSpectralPowerDistribution(
    comptime N: comptime_int,
    comptime WL_start: f32,
    comptime WL_end: f32,
) type {
    return struct {
        values: [N]f32 = undefined,

        var Cie = [_]Vec4f{@splat(4, @as(f32, -1.0))} ** N;
        const Step = (WL_end - WL_start) / @intToFloat(f32, N);

        const Self = @This();

        pub fn staticInit() void {
            if (Cie[0][0] >= 0.0) {
                return;
            }

            var CIE_X = Interpolated.init(&xyz.CIE_Wavelengths_360_830_1nm, &xyz.CIE_X_360_830_1nm);
            var CIE_Y = Interpolated.init(&xyz.CIE_Wavelengths_360_830_1nm, &xyz.CIE_Y_360_830_1nm);
            var CIE_Z = Interpolated.init(&xyz.CIE_Wavelengths_360_830_1nm, &xyz.CIE_Z_360_830_1nm);

            const cie_x = Self.initInterpolated(CIE_X);
            const cie_y = Self.initInterpolated(CIE_Y);
            const cie_z = Self.initInterpolated(CIE_Z);

            for (Cie) |*c, i| {
                c.* = Vec4f{ cie_x.values[i], cie_y.values[i], cie_z.values[i], 0.0 };
            }
        }

        pub fn randomWavelength(bin: usize, r: f32) f32 {
            return WL_start + (@intToFloat(f32, bin) + r) * Step;
        }

        pub fn wavelengthCenter(bin: usize) f32 {
            return WL_start + (@intToFloat(f32, bin) + 0.5) * Step;
        }

        pub fn initInterpolated(interpolated: Interpolated) Self {
            var result = Self{};

            for (result.values) |*v, i| {
                const a = WL_start + @intToFloat(f32, i) * Step;
                const b = a + Step;

                v.* = interpolated.integrate(a, b) / Step;
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
