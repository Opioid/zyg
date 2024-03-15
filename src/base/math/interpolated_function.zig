const math = @import("math.zig");
const Vec2i = math.Vec2i;
const Vec2u = math.Vec2u;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn InterpolatedFunction1D(comptime T: type) type {
    return struct {
        range_end: f32 = undefined,
        inverse_interval: f32 = undefined,

        samples: []T = &.{},

        const Self = @This();

        pub fn init(alloc: Allocator, range_begin: f32, range_end: f32, num_samples: u32) !Self {
            const range = range_end - range_begin;
            const interval = range / @as(f32, @floatFromInt(num_samples - 1));

            return Self{
                .range_end = range_end,
                .inverse_interval = 1.0 / interval,
                .samples = try alloc.alloc(T, num_samples),
            };
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            alloc.free(self.samples);
        }

        pub fn eval(self: Self, x: f32) T {
            const cx = math.min(x, self.range_end);
            const o = cx * self.inverse_interval;
            const offset: u32 = @intFromFloat(o);
            const t = o - @as(f32, @floatFromInt(offset));

            return math.lerp(
                self.samples[offset],
                self.samples[@min(offset + 1, @as(u32, @intCast(self.samples.len - 1)))],
                @as(Vec4f, @splat(t)),
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

        pub fn init(alloc: Allocator, range_begin: Vec2f, range_end: Vec2f, num_samples: Vec2u) !Self {
            const range = range_end - range_begin;
            const interval = range / (@as(Vec2u, @floatFromInt(num_samples)) - Vec2u{ 1, 1 });

            return Self{
                .num_samples = num_samples,
                .range_end = range_end,
                .inverse_interval = @as(Vec2f, @splat(1.0)) / interval,
                .samples = try alloc.alloc(T, num_samples[0] * num_samples[1]),
            };
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            alloc.free(self.samples);
        }

        pub fn set(self: *Self, x: u32, y: u32, v: T) void {
            self.samples[y * self.num_samples[0] + x] = v;
        }

        pub fn eval(self: Self, x: f32, y: f32) T {
            const cx = math.min(x, self.range_end[0]);
            const cy = math.min(y, self.range_end[1]);

            const o = Vec2f{ cx, cy } * self.inverse_interval;
            const offset = math.vec2fTo2u(o);
            const t = o - math.vec2uTo2f(offset);

            const col1 = @min(offset[0] + 1, self.num_samples[0] - 1);

            const row0 = offset[1] * self.num_samples[0];
            const row1 = @min(offset[1] + 1, self.num_samples[1] - 1) * self.num_samples[0];

            const c = [4]Vec4f{
                self.samples[offset[0] + row0],
                self.samples[col1 + row0],
                self.samples[offset[0] + row1],
                self.samples[col1 + row1],
            };

            return math.bilinear(Vec4f, c, t[0], t[1]);
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
            const interval = range / @as(f32, @floatFromInt(N - 1));

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

        pub fn fromArray(samples: [*]const f32) Self {
            var result = Self{
                .range_end = 1.0,
                .inverse_interval = @floatFromInt(N - 1),
            };

            for (&result.samples, 0..) |*s, i| {
                s.* = samples[i];
            }

            return result;
        }

        pub fn scale(self: *Self, x: f32) void {
            for (&self.samples) |*s| {
                s.* *= x;
            }
        }

        pub fn eval(self: Self, x: f32) f32 {
            const cx = math.min(x, self.range_end);
            const o = cx * self.inverse_interval;
            const offset = @as(u32, @intFromFloat(o));
            const t = o - @as(f32, @floatFromInt(offset));

            return math.lerp(
                self.samples[offset],
                self.samples[@min(offset + 1, N - 1)],
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

            for (&result.samples, 0..) |*s, i| {
                s.* = samples[i];
            }

            return result;
        }

        pub fn eval(self: Self, x: f32, y: f32) f32 {
            const mx = math.min(x, 1.0);
            const my = math.min(y, 1.0);

            const o = Vec2f{ mx, my } * Vec2f{ @floatFromInt(X - 1), @floatFromInt(Y - 1) };
            const offset: Vec2i = @intFromFloat(o);
            const t = o - @as(Vec2f, @floatFromInt(offset));

            const col1 = @min(offset[0] + 1, X - 1);
            const row0 = offset[1] * X;
            const row1 = @min(offset[1] + 1, Y - 1) * X;

            const c = [_]f32{
                self.samples[@intCast(offset[0] + row0)],
                self.samples[@intCast(col1 + row0)],
                self.samples[@intCast(offset[0] + row1)],
                self.samples[@intCast(col1 + row1)],
            };

            return math.bilinear(f32, c, t[0], t[1]);
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

            for (&result.samples, 0..) |*s, i| {
                s.* = samples[i];
            }

            return result;
        }

        pub fn eval(self: Self, x: f32, y: f32, z: f32) f32 {
            const v = Vec4f{ x, y, z, 0.0 };
            const mv = math.min4(v, @splat(1.0));

            const o = mv * Vec4f{
                @floatFromInt(X - 1),
                @floatFromInt(Y - 1),
                @floatFromInt(Z - 1),
                0.0,
            };

            const offset: Vec4i = @intFromFloat(o);
            const t = o - @as(Vec4f, @floatFromInt(offset));

            const col1 = @min(offset[0] + 1, X - 1);
            const row0 = offset[1] * X;
            const row1 = @min(offset[1] + 1, Y - 1) * X;

            const area = comptime X * Y;
            const slice0 = offset[2] * area;
            const slice1 = @min(offset[2] + 1, Z - 1) * area;

            const ca = [_]f32{
                self.samples[@intCast(offset[0] + row0 + slice0)],
                self.samples[@intCast(col1 + row0 + slice0)],
                self.samples[@intCast(offset[0] + row1 + slice0)],
                self.samples[@intCast(col1 + row1 + slice0)],
            };

            const cb = [_]f32{
                self.samples[@intCast(offset[0] + row0 + slice1)],
                self.samples[@intCast(col1 + row0 + slice1)],
                self.samples[@intCast(offset[0] + row1 + slice1)],
                self.samples[@intCast(col1 + row1 + slice1)],
            };

            const c0 = math.bilinear(f32, ca, t[0], t[1]);
            const c1 = math.bilinear(f32, cb, t[0], t[1]);

            return math.lerp(c0, c1, t[2]);
        }
    };
}
