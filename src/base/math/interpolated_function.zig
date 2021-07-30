usingnamespace @import("math.zig");

const std = @import("std");

pub fn InterpolatedFunction_1D_N(comptime N: u32) type {
    return struct {
        range_end: f32,
        inverse_interval: f32,

        samples: [N]f32 = undefined,

        const Self = @This();

        pub fn init(range_begin: f32, range_end: f32, f: anytype) Self {
            const range = range_end - range_begin;
            const interval = range / @intToFloat(f32, N - 1);

            var result = Self{ .range_end = range_end, .inverse_interval = 1.0 / interval };

            var i: u32 = 0;
            var s = range_begin;

            while (i < N) : (i += 1) {
                result.samples[i] = f.eval(s);

                s += interval;
            }

            return result;
        }

        pub fn scale(self: *Self, x: f32) void {
            for (self.samples) |*s| {
                s.* *= x;
            }
        }

        pub fn eval(self: Self, x: f32) f32 {
            const cx = std.math.min(x, self.range_end);
            const o = cx * self.inverse_interval;
            const offset = @floatToInt(u32, o);
            const t = o - @intToFloat(f32, offset);

            return lerp(self.samples[offset], self.samples[std.math.min(offset + 1, N - 1)], t);
        }
    };
}
