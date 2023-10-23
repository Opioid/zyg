const Sampler = @import("../../sampler/sampler.zig").Sampler;
const cs = @import("../../camera/camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const Tonemapper = @import("tonemapper.zig").Tonemapper;
const Result = @import("result.zig").Result;
const AovBuffer = @import("aov/aov_buffer.zig").Buffer;
const aovns = @import("aov/aov_value.zig");
const AovValue = aovns.Value;
const AovFactory = aovns.Factory;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Filtered(comptime T: type) type {
    return struct {
        const N = 30;
        const Func = math.InterpolatedFunction1D_N(N);

        sensor: T = .{},

        aov: AovBuffer = .{},

        dimensions: Vec2i = @splat(0),

        clamp_max: f32,

        radius: f32,
        radius_int: i32,

        filter: Func,

        distribution: math.Distribution2DN(N + 1) = .{},

        tonemapper: Tonemapper = Tonemapper.init(.Linear, 0.0),

        const Self = @This();

        pub fn init(clamp_max: f32, radius: f32, f: anytype) Self {
            @setEvalBranchQuota(7600);

            var result = Self{
                .clamp_max = clamp_max,
                .radius = radius,
                .radius_int = @intFromFloat(@ceil(radius)),
                .filter = Func.init(0.0, radius, f),
            };

            if (radius > 0.0) {
                result.filter.scale(1.0 / result.integral(64, radius));

                const interval = (2.0 * radius) / @as(f32, @floatFromInt(N));

                for (&result.distribution.conditional, 0..) |*c, y| {
                    const sy = -radius + @as(f32, @floatFromInt(y)) * interval;
                    const fy = f.eval(@abs(sy));

                    var data: [N + 1]f32 = undefined;

                    for (&data, 0..) |*d, x| {
                        const sx = -radius + @as(f32, @floatFromInt(x)) * interval;
                        d.* = @abs(fy * f.eval(@abs(sx)));
                    }

                    c.configure(data);
                }

                result.distribution.configure();
            }

            return result;
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            self.sensor.deinit(alloc);
            self.aov.deinit(alloc);
        }

        pub fn resize(self: *Self, alloc: Allocator, dimensions: Vec2i, factory: AovFactory) !void {
            self.dimensions = dimensions;

            const len = @as(usize, @intCast(dimensions[0] * dimensions[1]));

            try self.sensor.resize(alloc, len);
            try self.aov.resize(alloc, len, factory);
        }

        pub fn cameraSample(self: *const Self, pixel: Vec2i, sampler: *Sampler) Sample {
            const s4 = sampler.sample4D();
            const s1 = sampler.sample1D();

            sampler.incrementPadding();

            const pixel_uv = Vec2f{ s4[0], s4[1] };

            const o = if (0 == self.radius_int) pixel_uv else self.distribution.sampleContinous(pixel_uv).uv;
            const filter_uv = @as(Vec2f, @splat(self.radius)) * (@as(Vec2f, @splat(2.0)) * o - @as(Vec2f, @splat(1.0)));

            return .{
                .pixel = pixel,
                .filter_uv = filter_uv,
                .lens_uv = .{ s4[2], s4[3] },
                .time = s1,
            };
        }

        pub fn addSample(self: *Self, sample: Sample, color: Vec4f, aov: AovValue) Result {
            const w = self.eval(sample.filter_uv[0]) * self.eval(sample.filter_uv[1]);
            const weight: f32 = if (w < 0.0) -1.0 else 1.0;

            const pixel = sample.pixel;

            const d = self.dimensions;
            const id = @as(usize, @intCast(d[0] * pixel[1] + pixel[0]));

            if (aov.active()) {
                const len = AovValue.Num_classes;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const class = @as(AovValue.Class, @enumFromInt(i));
                    if (aov.activeClass(class)) {
                        const value = aov.values[i];

                        if (.Depth == class) {
                            self.aov.lessPixel(id, i, value[0]);
                        } else if (.MaterialId == class) {
                            self.aov.overwritePixel(id, i, value[0], weight);
                        } else if (.ShadingNormal == class) {
                            self.aov.addPixel(id, i, value, 1.0);
                        } else {
                            self.aov.addPixel(id, i, value, weight);
                        }
                    }
                }
            }

            return self.sensor.addPixel(id, self.clamp(color), weight);
        }

        pub fn splatSample(self: *Self, sample: SampleTo, color: Vec4f, bounds: Vec4i) void {
            const clamped = self.clamp(color);

            const pixel = sample.pixel;
            const x = pixel[0];
            const y = pixel[1];

            const pixel_uv = sample.pixel_uv;
            const ox = pixel_uv[0] - 0.5;
            const oy = pixel_uv[1] - 0.5;

            if (0 == self.radius_int) {
                const d = self.dimensions;
                const i = @as(usize, @intCast(d[0] * pixel[1] + pixel[0]));

                self.sensor.splatPixelAtomic(i, clamped, 1.0);
            } else if (1 == self.radius_int) {
                const wx0 = self.eval(ox + 1.0);
                const wx1 = self.eval(ox);
                const wx2 = self.eval(ox - 1.0);

                const wy0 = self.eval(oy + 1.0);
                const wy1 = self.eval(oy);
                const wy2 = self.eval(oy - 1.0);

                // 1. row
                self.splat(.{ x - 1, y - 1 }, wx0 * wy0, clamped, bounds);
                self.splat(.{ x, y - 1 }, wx1 * wy0, clamped, bounds);
                self.splat(.{ x + 1, y - 1 }, wx2 * wy0, clamped, bounds);

                // 2. row
                self.splat(.{ x - 1, y }, wx0 * wy1, clamped, bounds);
                self.splat(.{ x, y }, wx1 * wy1, clamped, bounds);
                self.splat(.{ x + 1, y }, wx2 * wy1, clamped, bounds);

                // 3. row
                self.splat(.{ x - 1, y + 1 }, wx0 * wy2, clamped, bounds);
                self.splat(.{ x, y + 1 }, wx1 * wy2, clamped, bounds);
                self.splat(.{ x + 1, y + 1 }, wx2 * wy2, clamped, bounds);
            } else if (2 == self.radius_int) {
                const wx0 = self.eval(ox + 2.0);
                const wx1 = self.eval(ox + 1.0);
                const wx2 = self.eval(ox);
                const wx3 = self.eval(ox - 1.0);
                const wx4 = self.eval(ox - 2.0);

                const wy0 = self.eval(oy + 2.0);
                const wy1 = self.eval(oy + 1.0);
                const wy2 = self.eval(oy);
                const wy3 = self.eval(oy - 1.0);
                const wy4 = self.eval(oy - 2.0);

                // 1. row
                self.splat(.{ x - 2, y - 2 }, wx0 * wy0, clamped, bounds);
                self.splat(.{ x - 1, y - 2 }, wx1 * wy0, clamped, bounds);
                self.splat(.{ x, y - 2 }, wx2 * wy0, clamped, bounds);
                self.splat(.{ x + 1, y - 2 }, wx3 * wy0, clamped, bounds);
                self.splat(.{ x + 2, y - 2 }, wx4 * wy0, clamped, bounds);

                // 2. row
                self.splat(.{ x - 2, y - 1 }, wx0 * wy1, clamped, bounds);
                self.splat(.{ x - 1, y - 1 }, wx1 * wy1, clamped, bounds);
                self.splat(.{ x, y - 1 }, wx2 * wy1, clamped, bounds);
                self.splat(.{ x + 1, y - 1 }, wx3 * wy1, clamped, bounds);
                self.splat(.{ x + 2, y - 1 }, wx4 * wy1, clamped, bounds);

                // 3. row
                self.splat(.{ x - 2, y }, wx0 * wy2, clamped, bounds);
                self.splat(.{ x - 1, y }, wx1 * wy2, clamped, bounds);
                self.splat(.{ x, y }, wx2 * wy2, clamped, bounds);
                self.splat(.{ x + 1, y }, wx3 * wy2, clamped, bounds);
                self.splat(.{ x + 2, y }, wx4 * wy2, clamped, bounds);

                // 4. row
                self.splat(.{ x - 2, y + 1 }, wx0 * wy3, clamped, bounds);
                self.splat(.{ x - 1, y + 1 }, wx1 * wy3, clamped, bounds);
                self.splat(.{ x, y + 1 }, wx2 * wy3, clamped, bounds);
                self.splat(.{ x + 1, y + 1 }, wx3 * wy3, clamped, bounds);
                self.splat(.{ x + 2, y + 1 }, wx4 * wy3, clamped, bounds);

                // 5. row
                self.splat(.{ x - 2, y + 2 }, wx0 * wy4, clamped, bounds);
                self.splat(.{ x - 1, y + 2 }, wx1 * wy4, clamped, bounds);
                self.splat(.{ x, y + 2 }, wx2 * wy4, clamped, bounds);
                self.splat(.{ x + 1, y + 2 }, wx3 * wy4, clamped, bounds);
                self.splat(.{ x + 2, y + 2 }, wx4 * wy4, clamped, bounds);
            }
        }

        fn splat(self: *Self, pixel: Vec2i, weight: f32, color: Vec4f, bounds: Vec4i) void {
            if (@as(u32, @bitCast(pixel[0] - bounds[0])) <= @as(u32, @bitCast(bounds[2])) and
                @as(u32, @bitCast(pixel[1] - bounds[1])) <= @as(u32, @bitCast(bounds[3])))
            {
                const d = self.dimensions;
                const i = @as(usize, @intCast(d[0] * pixel[1] + pixel[0]));
                self.sensor.splatPixelAtomic(i, color, weight);
            }
        }
        inline fn clamp(self: *const Self, color: Vec4f) Vec4f {
            const mc = math.hmax3(color);
            const max = self.clamp_max;

            if (mc > max) {
                const r = max / mc;
                const s = @as(Vec4f, @splat(r)) * color;
                return .{ s[0], s[1], s[2], color[3] };
            }

            return color;
        }

        inline fn eval(self: *const Self, s: f32) f32 {
            return self.filter.eval(@abs(s));
        }

        fn integral(self: *const Self, num_samples: u32, radius: f32) f32 {
            const interval = radius / @as(f32, @floatFromInt(num_samples));
            var s = 0.5 * interval;
            var sum: f32 = 0.0;
            var i: u32 = 0;

            while (i < num_samples) : (i += 1) {
                const v = self.eval(s);
                const a = v * interval;

                sum += a;
                s += interval;
            }

            return sum + sum;
        }
    };
}
