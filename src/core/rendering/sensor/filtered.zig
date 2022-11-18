const cs = @import("../../sampler/camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const Tonemapper = @import("tonemapper.zig").Tonemapper;
const AovBuffer = @import("aov/aov_buffer.zig").Buffer;
const aovns = @import("aov/aov_value.zig");
const AovValue = aovns.Value;
const AovFactory = aovns.Factory;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Filtered(comptime T: type) type {
    return struct {
        const Func = math.InterpolatedFunction1D_N(30);

        sensor: T = .{},

        aov: AovBuffer = .{},

        dimensions: Vec2i = @splat(2, @as(i32, 0)),

        clamp_max: f32,

        radius_int: i32,

        filter: Func,

        tonemapper: Tonemapper = Tonemapper.init(.Linear, 0.0),

        const Self = @This();

        pub fn init(clamp_max: f32, radius: f32, f: anytype) Self {
            var result = Self{
                .clamp_max = clamp_max,
                .radius_int = @floatToInt(i32, @ceil(radius)),
                .filter = Func.init(0.0, radius, f),
            };

            if (radius > 0.0) {
                result.filter.scale(1.0 / result.integral(64, radius));
            }

            return result;
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            self.sensor.deinit(alloc);
            self.aov.deinit(alloc);
        }

        pub fn resize(self: *Self, alloc: Allocator, dimensions: Vec2i, factory: AovFactory) !void {
            self.dimensions = dimensions;

            const len = @intCast(usize, dimensions[0] * dimensions[1]);

            try self.sensor.resize(alloc, len);
            try self.aov.resize(alloc, len, factory);
        }

        pub fn addSample(self: *Self, sample: Sample, color: Vec4f, aov: AovValue, bounds: Vec4i, isolated: Vec4i) void {
            const clamped = self.clamp(color);

            const pixel = sample.pixel;
            const x = pixel[0];
            const y = pixel[1];

            const pixel_uv = sample.pixel_uv;
            const ox = pixel_uv[0] - 0.5;
            const oy = pixel_uv[1] - 0.5;

            if (0 == self.radius_int) {
                const d = self.dimensions;
                const id = @intCast(usize, d[0] * pixel[1] + pixel[0]);

                self.sensor.addPixel(id, clamped, 1.0);

                if (aov.active()) {
                    const len = AovValue.Num_classes;
                    var i: u32 = 0;
                    while (i < len) : (i += 1) {
                        const class = @intToEnum(AovValue.Class, i);
                        if (aov.activeClass(class)) {
                            const value = aov.values[i];

                            if (.Depth == class) {
                                self.lessAov(pixel, i, value[0], bounds);
                            } else if (.MaterialId == class) {
                                self.overwriteAov(pixel, i, 1.0, value[0], bounds);
                            } else {
                                self.addAov(pixel, i, 1.0, value, bounds, isolated);
                            }
                        }
                    }
                }
            } else if (1 == self.radius_int) {
                const wx0 = self.eval(ox + 1.0);
                const wx1 = self.eval(ox);
                const wx2 = self.eval(ox - 1.0);

                const wy0 = self.eval(oy + 1.0);
                const wy1 = self.eval(oy);
                const wy2 = self.eval(oy - 1.0);

                // 1. row
                self.add(.{ x - 1, y - 1 }, wx0 * wy0, clamped, bounds, isolated);
                self.add(.{ x, y - 1 }, wx1 * wy0, clamped, bounds, isolated);
                self.add(.{ x + 1, y - 1 }, wx2 * wy0, clamped, bounds, isolated);

                // 2. row
                self.add(.{ x - 1, y }, wx0 * wy1, clamped, bounds, isolated);
                self.add(.{ x, y }, wx1 * wy1, clamped, bounds, isolated);
                self.add(.{ x + 1, y }, wx2 * wy1, clamped, bounds, isolated);

                // 3. row
                self.add(.{ x - 1, y + 1 }, wx0 * wy2, clamped, bounds, isolated);
                self.add(.{ x, y + 1 }, wx1 * wy2, clamped, bounds, isolated);
                self.add(.{ x + 1, y + 1 }, wx2 * wy2, clamped, bounds, isolated);

                if (aov.active()) {
                    const len = AovValue.Num_classes;
                    var i: u32 = 0;
                    while (i < len) : (i += 1) {
                        const class = @intToEnum(AovValue.Class, i);
                        if (aov.activeClass(class)) {
                            const value = aov.values[i];

                            if (.Depth == class) {
                                self.lessAov(.{ x, y }, i, value[0], bounds);
                            } else if (.MaterialId == class) {
                                self.overwriteAov(.{ x, y }, i, wx2 * wy2, value[0], bounds);
                            } else if (.ShadingNormal == class) {
                                self.addAov(.{ x, y }, i, 1.0, value, bounds, isolated);
                            } else {
                                // 1. row
                                self.addAov(.{ x - 1, y - 1 }, i, wx0 * wy0, value, bounds, isolated);
                                self.addAov(.{ x, y - 1 }, i, wx1 * wy0, value, bounds, isolated);
                                self.addAov(.{ x + 1, y - 1 }, i, wx2 * wy0, value, bounds, isolated);

                                // 2. row
                                self.addAov(.{ x - 1, y }, i, wx0 * wy1, value, bounds, isolated);
                                self.addAov(.{ x, y }, i, wx1 * wy1, value, bounds, isolated);
                                self.addAov(.{ x + 1, y }, i, wx2 * wy1, value, bounds, isolated);

                                // 3. row
                                self.addAov(.{ x - 1, y + 1 }, i, wx0 * wy2, value, bounds, isolated);
                                self.addAov(.{ x, y + 1 }, i, wx1 * wy2, value, bounds, isolated);
                                self.addAov(.{ x + 1, y + 1 }, i, wx2 * wy2, value, bounds, isolated);
                            }
                        }
                    }
                }
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
                self.add(.{ x - 2, y - 2 }, wx0 * wy0, clamped, bounds, isolated);
                self.add(.{ x - 1, y - 2 }, wx1 * wy0, clamped, bounds, isolated);
                self.add(.{ x, y - 2 }, wx2 * wy0, clamped, bounds, isolated);
                self.add(.{ x + 1, y - 2 }, wx3 * wy0, clamped, bounds, isolated);
                self.add(.{ x + 2, y - 2 }, wx4 * wy0, clamped, bounds, isolated);

                // 2. row
                self.add(.{ x - 2, y - 1 }, wx0 * wy1, clamped, bounds, isolated);
                self.add(.{ x - 1, y - 1 }, wx1 * wy1, clamped, bounds, isolated);
                self.add(.{ x, y - 1 }, wx2 * wy1, clamped, bounds, isolated);
                self.add(.{ x + 1, y - 1 }, wx3 * wy1, clamped, bounds, isolated);
                self.add(.{ x + 2, y - 1 }, wx4 * wy1, clamped, bounds, isolated);

                // 3. row
                self.add(.{ x - 2, y }, wx0 * wy2, clamped, bounds, isolated);
                self.add(.{ x - 1, y }, wx1 * wy2, clamped, bounds, isolated);
                self.add(.{ x, y }, wx2 * wy2, clamped, bounds, isolated);
                self.add(.{ x + 1, y }, wx3 * wy2, clamped, bounds, isolated);
                self.add(.{ x + 2, y }, wx4 * wy2, clamped, bounds, isolated);

                // 4. row
                self.add(.{ x - 2, y + 1 }, wx0 * wy3, clamped, bounds, isolated);
                self.add(.{ x - 1, y + 1 }, wx1 * wy3, clamped, bounds, isolated);
                self.add(.{ x, y + 1 }, wx2 * wy3, clamped, bounds, isolated);
                self.add(.{ x + 1, y + 1 }, wx3 * wy3, clamped, bounds, isolated);
                self.add(.{ x + 2, y + 1 }, wx4 * wy3, clamped, bounds, isolated);

                // 5. row
                self.add(.{ x - 2, y + 2 }, wx0 * wy4, clamped, bounds, isolated);
                self.add(.{ x - 1, y + 2 }, wx1 * wy4, clamped, bounds, isolated);
                self.add(.{ x, y + 2 }, wx2 * wy4, clamped, bounds, isolated);
                self.add(.{ x + 1, y + 2 }, wx3 * wy4, clamped, bounds, isolated);
                self.add(.{ x + 2, y + 2 }, wx4 * wy4, clamped, bounds, isolated);

                if (aov.active()) {
                    const len = AovValue.Num_classes;
                    var i: u32 = 0;
                    while (i < len) : (i += 1) {
                        const class = @intToEnum(AovValue.Class, i);
                        if (aov.activeClass(class)) {
                            const value = aov.values[i];

                            if (.Depth == class) {
                                self.lessAov(.{ x, y }, i, value[0], bounds);
                            } else if (.MaterialId == class) {
                                self.overwriteAov(.{ x, y }, i, wx2 * wy2, value[0], bounds);
                            } else if (.ShadingNormal == class) {
                                self.addAov(.{ x, y }, i, 1.0, value, bounds, isolated);
                            } else {
                                // 1. row
                                self.addAov(.{ x - 2, y - 2 }, i, wx0 * wy0, value, bounds, isolated);
                                self.addAov(.{ x - 1, y - 2 }, i, wx1 * wy0, value, bounds, isolated);
                                self.addAov(.{ x, y - 2 }, i, wx2 * wy0, value, bounds, isolated);
                                self.addAov(.{ x + 1, y - 2 }, i, wx3 * wy0, value, bounds, isolated);
                                self.addAov(.{ x + 2, y - 2 }, i, wx4 * wy0, value, bounds, isolated);

                                // 2. row
                                self.addAov(.{ x - 2, y - 1 }, i, wx0 * wy1, value, bounds, isolated);
                                self.addAov(.{ x - 1, y - 1 }, i, wx1 * wy1, value, bounds, isolated);
                                self.addAov(.{ x, y - 1 }, i, wx2 * wy1, value, bounds, isolated);
                                self.addAov(.{ x + 1, y - 1 }, i, wx3 * wy1, value, bounds, isolated);
                                self.addAov(.{ x + 2, y - 1 }, i, wx4 * wy1, value, bounds, isolated);

                                // 3. row
                                self.addAov(.{ x - 2, y }, i, wx0 * wy2, value, bounds, isolated);
                                self.addAov(.{ x - 1, y }, i, wx1 * wy2, value, bounds, isolated);
                                self.addAov(.{ x, y }, i, wx2 * wy2, value, bounds, isolated);
                                self.addAov(.{ x + 1, y }, i, wx3 * wy2, value, bounds, isolated);
                                self.addAov(.{ x + 2, y }, i, wx4 * wy2, value, bounds, isolated);

                                // 4. row
                                self.addAov(.{ x - 2, y + 1 }, i, wx0 * wy3, value, bounds, isolated);
                                self.addAov(.{ x - 1, y + 1 }, i, wx1 * wy3, value, bounds, isolated);
                                self.addAov(.{ x, y + 1 }, i, wx2 * wy3, value, bounds, isolated);
                                self.addAov(.{ x + 1, y + 1 }, i, wx3 * wy3, value, bounds, isolated);
                                self.addAov(.{ x + 2, y + 1 }, i, wx4 * wy3, value, bounds, isolated);

                                // 5. row
                                self.addAov(.{ x - 2, y + 2 }, i, wx0 * wy4, value, bounds, isolated);
                                self.addAov(.{ x - 1, y + 2 }, i, wx1 * wy4, value, bounds, isolated);
                                self.addAov(.{ x, y + 2 }, i, wx2 * wy4, value, bounds, isolated);
                                self.addAov(.{ x + 1, y + 2 }, i, wx3 * wy4, value, bounds, isolated);
                                self.addAov(.{ x + 2, y + 2 }, i, wx4 * wy4, value, bounds, isolated);
                            }
                        }
                    }
                }
            }
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
                const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);

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
            if (@bitCast(u32, pixel[0] - bounds[0]) <= @bitCast(u32, bounds[2]) and
                @bitCast(u32, pixel[1] - bounds[1]) <= @bitCast(u32, bounds[3]))
            {
                const d = self.dimensions;
                const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);
                self.sensor.splatPixelAtomic(i, color, weight);
            }
        }

        fn add(self: *Self, pixel: Vec2i, weight: f32, color: Vec4f, bounds: Vec4i, isolated: Vec4i) void {
            if (@bitCast(u32, pixel[0] - bounds[0]) <= @bitCast(u32, bounds[2]) and
                @bitCast(u32, pixel[1] - bounds[1]) <= @bitCast(u32, bounds[3]))
            {
                const d = self.dimensions;
                const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);

                if (@bitCast(u32, pixel[0] - isolated[0]) <= @bitCast(u32, isolated[2]) and
                    @bitCast(u32, pixel[1] - isolated[1]) <= @bitCast(u32, isolated[3]))
                {
                    self.sensor.addPixel(i, color, weight);
                } else {
                    self.sensor.addPixelAtomic(i, color, weight);
                }
            }
        }

        fn addAov(self: *Self, pixel: Vec2i, slot: u32, weight: f32, value: Vec4f, bounds: Vec4i, isolated: Vec4i) void {
            if (@bitCast(u32, pixel[0] - bounds[0]) <= @bitCast(u32, bounds[2]) and
                @bitCast(u32, pixel[1] - bounds[1]) <= @bitCast(u32, bounds[3]))
            {
                const d = self.dimensions;
                const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);

                if (@bitCast(u32, pixel[0] - isolated[0]) <= @bitCast(u32, isolated[2]) and
                    @bitCast(u32, pixel[1] - isolated[1]) <= @bitCast(u32, isolated[3]))
                {
                    self.aov.addPixel(i, slot, value, weight);
                } else {
                    self.aov.addPixelAtomic(i, slot, value, weight);
                }
            }
        }

        fn lessAov(self: *Self, pixel: Vec2i, slot: u32, value: f32, bounds: Vec4i) void {
            if (@bitCast(u32, pixel[0] - bounds[0]) <= @bitCast(u32, bounds[2]) and
                @bitCast(u32, pixel[1] - bounds[1]) <= @bitCast(u32, bounds[3]))
            {
                const d = self.dimensions;
                const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);

                self.aov.lessPixel(i, slot, value);
            }
        }

        fn overwriteAov(self: *Self, pixel: Vec2i, slot: u32, weight: f32, value: f32, bounds: Vec4i) void {
            if (@bitCast(u32, pixel[0] - bounds[0]) <= @bitCast(u32, bounds[2]) and
                @bitCast(u32, pixel[1] - bounds[1]) <= @bitCast(u32, bounds[3]))
            {
                const d = self.dimensions;
                const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);

                self.aov.overwritePixel(i, slot, value, weight);
            }
        }

        inline fn clamp(self: *const Self, color: Vec4f) Vec4f {
            const mc = math.maxComponent3(color);
            const max = self.clamp_max;

            if (mc > max) {
                const r = max / mc;
                const s = @splat(4, r) * color;
                return .{ s[0], s[1], s[2], color[3] };
            }

            return color;
        }

        fn eval(self: *const Self, s: f32) f32 {
            return self.filter.eval(@fabs(s));
        }

        fn integral(self: *const Self, num_samples: u32, radius: f32) f32 {
            const interval = radius / @intToFloat(f32, num_samples);
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
