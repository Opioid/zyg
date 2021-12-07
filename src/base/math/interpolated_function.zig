const math = @import("math.zig");
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub fn InterpolatedFunction1D_N(comptime N: comptime_int) type {
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

            return math.lerp(self.samples[offset], self.samples[std.math.min(offset + 1, N - 1)], t);
        }
    };
}

pub fn InterpolatedFunction2D_N(comptime X: comptime_int, comptime Y: comptime_int) type {
    return struct {
        samples: [X * Y]f32 = undefined,

        const Self = @This();

        pub fn fromArray(samples: [*]const f32) Self {
            @setEvalBranchQuota(1050);

            var result = Self{};

            for (result.samples) |*s, i| {
                s.* = samples[i];
            }

            return result;
        }

        pub fn eval(self: Self, x: f32, y: f32) f32 {
            const mx = std.math.min(x, 1.0);
            const my = std.math.min(y, 1.0);

            const o = Vec2f{ mx, my } * Vec2f{ @intToFloat(f32, X - 1), @intToFloat(f32, Y - 1) };
            const offset = math.vec2fTo2i(o);
            const t = o - math.vec2iTo2f(offset);

            const col1 = std.math.min(offset[0] + 1, X - 1);
            const row0 = offset[1] * X;
            const row1 = std.math.min(offset[1] + 1, Y - 1) * X;

            const c = [_]f32{
                self.samples[@intCast(u32, offset[0] + row0)],
                self.samples[@intCast(u32, col1 + row0)],
                self.samples[@intCast(u32, offset[0] + row1)],
                self.samples[@intCast(u32, col1 + row1)],
            };

            return math.bilinear1(c, t[0], t[1]);
        }
    };
}

pub fn InterpolatedFunction3D_N(comptime X: comptime_int, comptime Y: comptime_int, comptime Z: comptime_int) type {
    return struct {
        samples: [X * Y * Z]f32 = undefined,

        const Self = @This();

        pub fn fromArray(samples: [*]const f32) Self {
            @setEvalBranchQuota(32780);

            var result = Self{};

            for (result.samples) |*s, i| {
                s.* = samples[i];
            }

            return result;
        }

        pub fn eval(self: Self, x: f32, y: f32, z: f32) f32 {
            const mx = std.math.min(x, 1.0);
            const my = std.math.min(y, 1.0);
            const mz = std.math.min(z, 1.0);

            const o = Vec4f{ mx, my, mz, 0.0 } * Vec4f{
                @intToFloat(f32, X - 1),
                @intToFloat(f32, Y - 1),
                @intToFloat(f32, Z - 1),
                0.0,
            };

            const offset = math.vec4fTo4i(o);
            const t = o - math.vec4iTo4f(offset);

            const col1 = std.math.min(offset.v[0] + 1, X - 1);
            const row0 = offset.v[1] * X;
            const row1 = std.math.min(offset.v[1] + 1, Y - 1) * X;

            const area = comptime X * Y;
            const slice0 = offset.v[2] * area;
            const slice1 = std.math.min(offset.v[2] + 1, Z - 1) * area;

            const ca = [_]f32{
                self.samples[@intCast(u32, offset.v[0] + row0 + slice0)],
                self.samples[@intCast(u32, col1 + row0 + slice0)],
                self.samples[@intCast(u32, offset.v[0] + row1 + slice0)],
                self.samples[@intCast(u32, col1 + row1 + slice0)],
            };

            const cb = [_]f32{
                self.samples[@intCast(u32, offset.v[0] + row0 + slice1)],
                self.samples[@intCast(u32, col1 + row0 + slice1)],
                self.samples[@intCast(u32, offset.v[0] + row1 + slice1)],
                self.samples[@intCast(u32, col1 + row1 + slice1)],
            };

            const c0 = math.bilinear1(ca, t[0], t[1]);
            const c1 = math.bilinear1(cb, t[0], t[1]);

            return math.lerp(c0, c1, t[2]);
        }
    };
}
