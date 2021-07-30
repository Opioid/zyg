const Sample = @import("../../sampler/sampler.zig").Camera_sample;

const base = @import("base");
const Vec2i = base.math.Vec2i;
const Vec4i = base.math.Vec4i;
const Vec4f = base.math.Vec4f;

usingnamespace base.math.interpolated_function;

const std = @import("std");

pub fn Base(comptime T: type) type {
    return struct {
        const Func = InterpolatedFunction_1D_N(30);

        sensor: T = .{},

        filter: Func,

        const Self = @This();

        pub fn init(radius: f32, f: anytype) Self {
            var result = Self{ .filter = Func.init(0.0, radius, f) };

            result.filter.scale(1.0 / result.integral(64, radius));

            return result;
        }

        pub fn addWeighted(self: *Self, pixel: Vec2i, weight: f32, color: Vec4f, isolated: Vec4i, bounds: Vec4i) void {
            if (@bitCast(u32, pixel.v[0] - bounds.v[0]) <= @bitCast(u32, bounds.v[2]) and
                @bitCast(u32, pixel.v[1] - bounds.v[1]) <= @bitCast(u32, bounds.v[3]))
            {
                if (@bitCast(u32, pixel.v[0] - isolated.v[0]) <= @bitCast(u32, isolated.v[2]) and
                    @bitCast(u32, pixel.v[1] - isolated.v[1]) <= @bitCast(u32, isolated.v[3]))
                {
                    self.addPixel(pixel, color, weight);
                } else {
                    self.addPixelAtomic(pixel, color, weight);
                }
            }
        }

        pub fn eval(self: Self, s: f32) f32 {
            return self.filter.eval(std.math.fabs(s));
        }

        fn addPixel(self: *Self, pixel: Vec2i, color: Vec4f, weight: f32) void {
            self.sensor.addPixel(pixel, color, weight);
        }

        fn addPixelAtomic(self: *Self, pixel: Vec2i, color: Vec4f, weight: f32) void {
            self.sensor.addPixelAtomic(pixel, color, weight);
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

        pub fn init(radius: f32, f: anytype) Self {
            return .{ .base = Base(T).init(radius, f) };
        }

        pub fn addSample(self: *Self, sample: Sample, color: Vec4f, offset: Vec2i, isolated: Vec4i, bounds: Vec4i) void {
            const x = offset.v[0] + sample.pixel.v[0];
            const y = offset.v[1] + sample.pixel.v[1];

            const ox = sample.pixel_uv.v[0] - 0.5;
            const oy = sample.pixel_uv.v[1] - 0.5;

            const wx0 = self.base.eval(ox + 1.0);
            const wx1 = self.base.eval(ox);
            const wx2 = self.base.eval(ox - 1.0);

            const wy0 = self.base.eval(oy + 1.0);
            const wy1 = self.base.eval(oy);
            const wy2 = self.base.eval(oy - 1.0);

            const clamped = color;

            // 1. row
            self.base.addWeighted(Vec2i.init2(x - 1, y - 1), wx0 * wy0, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x, y - 1), wx1 * wy0, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x + 1, y - 1), wx2 * wy0, clamped, isolated, bounds);

            // 2. row
            self.base.addWeighted(Vec2i.init2(x - 1, y), wx0 * wy1, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x, y), wx1 * wy1, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x + 1, y), wx2 * wy1, clamped, isolated, bounds);

            // 3. row
            self.base.addWeighted(Vec2i.init2(x - 1, y + 1), wx0 * wy2, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x, y + 1), wx1 * wy2, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x + 1, y + 1), wx2 * wy2, clamped, isolated, bounds);
        }
    };
}

pub fn Filtered_2p0(comptime T: type) type {
    return struct {
        base: Base(T),

        const Self = @This();

        pub fn init(radius: f32, f: anytype) Self {
            return .{ .base = Base(T).init(radius, f) };
        }

        pub fn addSample(self: *Self, sample: Sample, color: Vec4f, offset: Vec2i, isolated: Vec4i, bounds: Vec4i) void {
            const x = offset.v[0] + sample.pixel.v[0];
            const y = offset.v[1] + sample.pixel.v[1];

            const ox = sample.pixel_uv.v[0] - 0.5;
            const oy = sample.pixel_uv.v[1] - 0.5;

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

            const clamped = color;

            // 1. row
            self.base.addWeighted(Vec2i.init2(x - 2, y - 2), wx0 * wy0, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x - 1, y - 2), wx1 * wy0, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x, y - 2), wx2 * wy0, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x + 1, y - 2), wx3 * wy0, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x + 2, y - 2), wx4 * wy0, clamped, isolated, bounds);

            // 2. row
            self.base.addWeighted(Vec2i.init2(x - 2, y - 1), wx0 * wy1, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x - 1, y - 1), wx1 * wy1, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x, y - 1), wx2 * wy1, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x + 1, y - 1), wx3 * wy1, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x + 2, y - 1), wx4 * wy1, clamped, isolated, bounds);

            // 3. row
            self.base.addWeighted(Vec2i.init2(x - 2, y), wx0 * wy2, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x - 1, y), wx1 * wy2, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x, y), wx2 * wy2, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x + 1, y), wx3 * wy2, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x + 2, y), wx4 * wy2, clamped, isolated, bounds);

            // 4. row
            self.base.addWeighted(Vec2i.init2(x - 2, y + 1), wx0 * wy3, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x - 1, y + 1), wx1 * wy3, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x, y + 1), wx2 * wy3, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x + 1, y + 1), wx3 * wy3, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x + 2, y + 1), wx4 * wy3, clamped, isolated, bounds);

            // 5. row
            self.base.addWeighted(Vec2i.init2(x - 2, y + 2), wx0 * wy4, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x - 1, y + 2), wx1 * wy4, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x, y + 2), wx2 * wy4, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x + 1, y + 2), wx3 * wy4, clamped, isolated, bounds);
            self.base.addWeighted(Vec2i.init2(x + 2, y + 2), wx4 * wy4, clamped, isolated, bounds);
        }
    };
}
