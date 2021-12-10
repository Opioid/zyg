const math = @import("math.zig");
const Vec2i = math.Vec2i;
const Vec2u = math.Vec2u;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn InterpolatedFunction1D(comptime T: type) type {
    return struct {
        range_end: f32 = undefined,
        inverse_interval: f32 = undefined,

        samples: []T = &.{},

        const Self = @This();

        pub fn init(alloc: *Allocator, range_begin: f32, range_end: f32, num_samples: u32) !Self {
            const range = range_end - range_begin;
            const interval = range / @intToFloat(f32, num_samples - 1);

            return Self{
                .range_end = range_end,
                .inverse_interval = 1.0 / interval,
                .samples = try alloc.alloc(T, num_samples),
            };
        }

        pub fn deinit(self: *Self, alloc: *Allocator) void {
            alloc.free(self.samples);
        }

        pub fn eval(self: Self, x: f32) T {
            const cx = std.math.min(x, self.range_end);
            const o = cx * self.inverse_interval;
            const offset = @floatToInt(u32, o);
            const t = o - @intToFloat(f32, offset);

            return math.lerp3(
                self.samples[offset],
                self.samples[std.math.min(offset + 1, @intCast(u32, self.samples.len - 1))],
                t,
            );
        }
    };
}

pub fn InterpolatedFunction2D(comptime T: type) type {
    return struct {
        num_samples: Vec2u = undefined,
        range_end: Vec2f = undefined,
        inverse_interval: Vec2f = undefined,

        samples: []T = &.{},

        const Self = @This();

        pub fn init(alloc: *Allocator, range_begin: Vec2f, range_end: Vec2f, num_samples: Vec2u) !Self {
            const range = range_end - range_begin;
            const interval = range / math.vec2uTo2f(num_samples - Vec2u{ 1, 1 });

            return Self{
                .num_samples = num_samples,
                .range_end = range_end,
                .inverse_interval = @splat(2, @as(f32, 1.0)) / interval,
                .samples = try alloc.alloc(T, num_samples[0] * num_samples[1]),
            };
        }

        pub fn deinit(self: *Self, alloc: *Allocator) void {
            alloc.free(self.samples);
        }

        pub fn set(self: *Self, x: u32, y: u32, v: T) void {
            self.samples[y * self.num_samples[0] + x] = v;
        }

        pub fn eval(self: Self, x: f32, y: f32) T {
            const cx = std.math.min(x, self.range_end[0]);
            const cy = std.math.min(y, self.range_end[1]);

            const o = Vec2f{ cx, cy } * self.inverse_interval;
            const offset = math.vec2fTo2u(o);
            const t = o - math.vec2uTo2f(offset);

            const col1 = std.math.min(offset[0] + 1, self.num_samples[0] - 1);

            const row0 = offset[1] * self.num_samples[0];
            const row1 = std.math.min(offset[1] + 1, self.num_samples[1] - 1) * self.num_samples[0];

            const c = [4]Vec4f{
                self.samples[offset[0] + row0],
                self.samples[col1 + row0],
                self.samples[offset[0] + row1],
                self.samples[col1 + row1],
            };

            return math.bilinear3(c, t[0], t[1]);
        }
    };
}

pub fn InterpolatedFunction1D_N(comptime N: comptime_int) type {
    return struct {
        range_end: f32,
        inverse_interval: f32,

        samples: [N]f32 = undefined,

        const Self = @This();

        pub fn init(range_begin: f32, range_end: f32, f: anytype) Self {
            const range = range_end - range_begin;
            const interval = range / @intToFloat(f32, N - 1);

            var result = Self{
                .range_end = range_end,
                .inverse_interval = 1.0 / interval,
            };

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

            return math.lerp(
                self.samples[offset],
                self.samples[std.math.min(offset + 1, N - 1)],
                t,
            );
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
