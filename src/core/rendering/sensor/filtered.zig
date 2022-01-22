const cs = @import("../../sampler/camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const Result = @import("base.zig").Base.Result;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");

pub fn Base(comptime T: type) type {
    return struct {
        const Func = math.InterpolatedFunction1D_N(30);

        sensor: T,

        radius: f32,

        filter: Func,

        distribution: math.Distribution2DN(31) = .{},

        const Self = @This();

        pub fn init(clamp_max: f32, radius: f32, f: anytype) Self {
            var result = Self{ .sensor = T.init(clamp_max), .radius = radius, .filter = Func.init(0.0, radius, f) };

            result.filter.scale(1.0 / result.integral(64, radius));

            const N: u32 = comptime result.distribution.conditional.len;

            const interval = (2.0 * radius) / @intToFloat(f32, N - 1);

            for (result.distribution.conditional) |*c, y| {
                const sy = -radius + @intToFloat(f32, y) * interval;
                const fy = f.eval(@fabs(sy));

                var data: [N]f32 = undefined;

                for (data) |*d, x| {
                    const sx = -radius + @intToFloat(f32, x) * interval;
                    d.* = @fabs(fy * f.eval(@fabs(sx)));
                }

                c.configure(data);
            }

            result.distribution.configure();

            return result;
        }

        pub fn pixelToImageCoordinates(self: Self, sample: *Sample) Vec2f {
            const o = self.distribution.sampleContinous(sample.pixel_uv).uv;
            const center = math.vec2iTo2f(sample.pixel) + @splat(2, @as(f32, 0.5));

            const filter_uv = @splat(2, self.radius) * (@splat(2, @as(f32, 2.0)) * o - @splat(2, @as(f32, 1.0)));
            sample.pixel_uv = filter_uv;

            return center + filter_uv;
        }

        pub fn splat(
            self: *Self,
            pixel: Vec2i,
            weight: f32,
            color: Vec4f,
            bounds: Vec4i,
        ) void {
            if (@bitCast(u32, pixel[0] - bounds[0]) <= @bitCast(u32, bounds[2]) and
                @bitCast(u32, pixel[1] - bounds[1]) <= @bitCast(u32, bounds[3]))
            {
                self.sensor.splatPixelAtomic(pixel, color, weight);
            }
        }

        pub fn eval(self: Self, s: f32) f32 {
            return self.filter.eval(@fabs(s));
        }

        fn integral(self: Self, num_samples: u32, radius: f32) f32 {
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

pub fn Filtered_1p0(comptime T: type) type {
    return struct {
        base: Base(T),

        const Self = @This();

        pub fn init(clamp_max: f32, radius: f32, f: anytype) Self {
            return .{ .base = Base(T).init(clamp_max, radius, f) };
        }

        pub fn addSample(self: *Self, sample: Sample, color: Vec4f, offset: Vec2i) Result {
            const x = offset[0] + sample.pixel[0];
            const y = offset[1] + sample.pixel[1];

            const w = self.base.eval(sample.pixel_uv[0]) * self.base.eval(sample.pixel_uv[1]);
            const weight: f32 = if (w < 0.0) -1.0 else 1.0;

            const clamped = self.base.sensor.base.clamp(color);
            return self.base.sensor.addPixel(.{ x, y }, clamped, weight);
        }

        pub fn splatSample(self: *Self, sample: SampleTo, color: Vec4f, offset: Vec2i, bounds: Vec4i) void {
            const x = offset[0] + sample.pixel[0];
            const y = offset[1] + sample.pixel[1];

            const ox = sample.pixel_uv[0] - 0.5;
            const oy = sample.pixel_uv[1] - 0.5;

            const wx0 = self.base.eval(ox + 1.0);
            const wx1 = self.base.eval(ox);
            const wx2 = self.base.eval(ox - 1.0);

            const wy0 = self.base.eval(oy + 1.0);
            const wy1 = self.base.eval(oy);
            const wy2 = self.base.eval(oy - 1.0);

            const clamped = self.base.sensor.base.clamp(color);

            // 1. row
            self.base.splat(.{ x - 1, y - 1 }, wx0 * wy0, clamped, bounds);
            self.base.splat(.{ x, y - 1 }, wx1 * wy0, clamped, bounds);
            self.base.splat(.{ x + 1, y - 1 }, wx2 * wy0, clamped, bounds);

            // 2. row
            self.base.splat(.{ x - 1, y }, wx0 * wy1, clamped, bounds);
            self.base.splat(.{ x, y }, wx1 * wy1, clamped, bounds);
            self.base.splat(.{ x + 1, y }, wx2 * wy1, clamped, bounds);

            // 3. row
            self.base.splat(.{ x - 1, y + 1 }, wx0 * wy2, clamped, bounds);
            self.base.splat(.{ x, y + 1 }, wx1 * wy2, clamped, bounds);
            self.base.splat(.{ x + 1, y + 1 }, wx2 * wy2, clamped, bounds);
        }
    };
}

pub fn Filtered_2p0(comptime T: type) type {
    return struct {
        base: Base(T),

        const Self = @This();

        pub fn init(clamp_max: f32, radius: f32, f: anytype) Self {
            return .{ .base = Base(T).init(clamp_max, radius, f) };
        }

        pub fn addSample(self: *Self, sample: Sample, color: Vec4f, offset: Vec2i) Result {
            const x = offset[0] + sample.pixel[0];
            const y = offset[1] + sample.pixel[1];

            const w = self.base.eval(sample.pixel_uv[0]) * self.base.eval(sample.pixel_uv[1]);
            const weight: f32 = if (w < 0.0) -1.0 else 1.0;

            const clamped = self.base.sensor.base.clamp(color);
            return self.base.sensor.addPixel(.{ x, y }, clamped, weight);
        }

        pub fn splatSample(self: *Self, sample: SampleTo, color: Vec4f, offset: Vec2i, bounds: Vec4i) void {
            const x = offset[0] + sample.pixel[0];
            const y = offset[1] + sample.pixel[1];

            const ox = sample.pixel_uv[0] - 0.5;
            const oy = sample.pixel_uv[1] - 0.5;

            const wx0 = self.base.eval(ox + 2.0);
            const wx1 = self.base.eval(ox + 1.0);
            const wx2 = self.base.eval(ox);
            const wx3 = self.base.eval(ox - 1.0);
            const wx4 = self.base.eval(ox - 2.0);

            const wy0 = self.base.eval(oy + 2.0);
            const wy1 = self.base.eval(oy + 1.0);
            const wy2 = self.base.eval(oy);
            const wy3 = self.base.eval(oy - 1.0);
            const wy4 = self.base.eval(oy - 2.0);

            const clamped = self.base.sensor.base.clamp(color);

            // 1. row
            self.base.splat(.{ x - 2, y - 2 }, wx0 * wy0, clamped, bounds);
            self.base.splat(.{ x - 1, y - 2 }, wx1 * wy0, clamped, bounds);
            self.base.splat(.{ x, y - 2 }, wx2 * wy0, clamped, bounds);
            self.base.splat(.{ x + 1, y - 2 }, wx3 * wy0, clamped, bounds);
            self.base.splat(.{ x + 2, y - 2 }, wx4 * wy0, clamped, bounds);

            // 2. row
            self.base.splat(.{ x - 2, y - 1 }, wx0 * wy1, clamped, bounds);
            self.base.splat(.{ x - 1, y - 1 }, wx1 * wy1, clamped, bounds);
            self.base.splat(.{ x, y - 1 }, wx2 * wy1, clamped, bounds);
            self.base.splat(.{ x + 1, y - 1 }, wx3 * wy1, clamped, bounds);
            self.base.splat(.{ x + 2, y - 1 }, wx4 * wy1, clamped, bounds);

            // 3. row
            self.base.splat(.{ x - 2, y }, wx0 * wy2, clamped, bounds);
            self.base.splat(.{ x - 1, y }, wx1 * wy2, clamped, bounds);
            self.base.splat(.{ x, y }, wx2 * wy2, clamped, bounds);
            self.base.splat(.{ x + 1, y }, wx3 * wy2, clamped, bounds);
            self.base.splat(.{ x + 2, y }, wx4 * wy2, clamped, bounds);

            // 4. row
            self.base.splat(.{ x - 2, y + 1 }, wx0 * wy3, clamped, bounds);
            self.base.splat(.{ x - 1, y + 1 }, wx1 * wy3, clamped, bounds);
            self.base.splat(.{ x, y + 1 }, wx2 * wy3, clamped, bounds);
            self.base.splat(.{ x + 1, y + 1 }, wx3 * wy3, clamped, bounds);
            self.base.splat(.{ x + 2, y + 1 }, wx4 * wy3, clamped, bounds);

            // 5. row
            self.base.splat(.{ x - 2, y + 2 }, wx0 * wy4, clamped, bounds);
            self.base.splat(.{ x - 1, y + 2 }, wx1 * wy4, clamped, bounds);
            self.base.splat(.{ x, y + 2 }, wx2 * wy4, clamped, bounds);
            self.base.splat(.{ x + 1, y + 2 }, wx3 * wy4, clamped, bounds);
            self.base.splat(.{ x + 2, y + 2 }, wx4 * wy4, clamped, bounds);
        }
    };
}
