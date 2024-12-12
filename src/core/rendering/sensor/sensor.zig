pub const Buffer = @import("buffer.zig").Buffer;
const AovBuffer = @import("aov/aov_buffer.zig").Buffer;
const aovns = @import("aov/aov_value.zig");
const AovValue = aovns.Value;
const AovFactory = aovns.Factory;
pub const Tonemapper = @import("tonemapper.zig").Tonemapper;
const cs = @import("../../camera/camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const IValue = @import("../integrator/helper.zig").IValue;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Pack4f = math.Pack4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Blackman = struct {
    r: f32,

    pub fn eval(self: Blackman, x: f32) f32 {
        const a0 = 0.35875;
        const a1 = 0.48829;
        const a2 = 0.14128;
        const a3 = 0.01168;

        const b = (std.math.pi * (x + self.r)) / self.r;

        return a0 - a1 * @cos(b) + a2 * @cos(2.0 * b) - a3 * @cos(3.0 * b);
    }
};

pub const Mitchell = struct {
    b: f32,
    c: f32,

    pub fn eval(self: Mitchell, x: f32) f32 {
        const b = self.b;
        const c = self.c;
        const xx = x * x;

        if (x > 1.0) {
            return ((-b - 6.0 * c) * xx * x + (6.0 * b + 30.0 * c) * xx +
                (-12.0 * b - 48.0 * c) * x + (8.0 * b + 24.0 * c)) / 6.0;
        }

        return ((12.0 - 9.0 * b - 6.0 * c) * xx * x + (-18.0 + 12.0 * b + 6.0 * c) * xx + (6.0 - 2.0 * b)) / 6.0;
    }
};

pub const Sensor = struct {
    const N = 30;
    const Func = math.InterpolatedFunction1D_N(N);

    const Layer = struct {
        buffer: Buffer,
        aov: AovBuffer,
        aov_noise_buffer: []f32 = &.{},

        fn deinit(self: *Layer, alloc: Allocator) void {
            self.buffer.deinit(alloc);
            self.aov.deinit(alloc);
            alloc.free(self.aov_noise_buffer);
        }

        fn resize(self: *Layer, alloc: Allocator, len: usize, factory: AovFactory, aov_noise: bool) !void {
            try self.buffer.resize(alloc, len);
            try self.aov.resize(alloc, len, factory);

            if (aov_noise and len > self.aov_noise_buffer.len) {
                self.aov_noise_buffer = try alloc.realloc(self.aov_noise_buffer, len);
            }
        }

        pub fn clearNoiseAov(self: *Layer) void {
            for (self.aov_noise_buffer) |*n| {
                n.* = 0.0;
            }
        }
    };

    class: Buffer.Class,

    layers: []Layer,

    dimensions: Vec2i,

    clamp_max: f32,

    filter_radius: f32,
    filter_radius_int: i32,

    filter: Func,

    distribution: math.Distribution2DN(N + 1) = .{},

    tonemapper: Tonemapper = Tonemapper.init(.Linear, 0.0),

    const Self = @This();

    pub fn init(class: Buffer.Class, clamp_max: f32, radius: f32, f: anytype) Self {
        @setEvalBranchQuota(7600);

        var result = Self{
            .class = class,
            .layers = &.{},
            .dimensions = @splat(0),
            .clamp_max = clamp_max,
            .filter_radius = radius,
            .filter_radius_int = @intFromFloat(@ceil(radius)),
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
        for (self.layers) |*l| {
            l.deinit(alloc);
        }
    }

    pub fn resize(self: *Self, alloc: Allocator, dimensions: Vec2i, num_layers: u32, factory: AovFactory, aov_noise: bool) !void {
        self.dimensions = dimensions;

        if (self.layers.len < num_layers) {
            for (self.layers) |*l| {
                l.deinit(alloc);
            }

            self.layers = try alloc.realloc(self.layers, num_layers);
            for (self.layers[0..num_layers]) |*l| {
                l.buffer = Buffer.init(self.class);
                l.aov = .{};
            }
        }

        const len: usize = @intCast(dimensions[0] * dimensions[1]);

        for (self.layers[0..num_layers]) |*l| {
            try l.resize(alloc, len, factory, aov_noise);
        }
    }

    pub fn cameraSample(self: *const Self, pixel: Vec2i, sampler: *Sampler) Sample {
        const s4 = sampler.sample4D();
        const s1 = sampler.sample1D();

        sampler.incrementPadding();

        const pixel_uv = Vec2f{ s4[0], s4[1] };

        const o = if (0 == self.filter_radius_int) pixel_uv else self.distribution.sampleContinous(pixel_uv).uv;
        const filter_uv = @as(Vec2f, @splat(self.filter_radius)) * (@as(Vec2f, @splat(2.0)) * o - @as(Vec2f, @splat(1.0)));

        return .{
            .pixel = pixel,
            .filter_uv = filter_uv,
            .lens_uv = .{ s4[2], s4[3] },
            .time = s1,
        };
    }

    pub fn addSample(self: *Sensor, layer_id: u32, sample: Sample, value: IValue, aov: AovValue) Vec4f {
        const w = self.eval(sample.filter_uv[0]) * self.eval(sample.filter_uv[1]);
        const weight: f32 = if (w < 0.0) -1.0 else 1.0;

        const pixel = sample.pixel;

        const d = self.dimensions;
        const id: u32 = @intCast(d[0] * pixel[1] + pixel[0]);

        var layer = &self.layers[layer_id];

        if (aov.active()) {
            const len = AovValue.Num_classes;
            var i: u32 = 0;
            while (i < len) : (i += 1) {
                const class = @as(AovValue.Class, @enumFromInt(i));
                if (aov.activeClass(class)) {
                    const avalue = aov.values[i];

                    if (.Depth == class) {
                        layer.aov.lessPixel(id, i, avalue[0]);
                    } else if (.MaterialId == class) {
                        layer.aov.overwritePixel(id, i, avalue[0], weight);
                    } else if (.ShadingNormal == class) {
                        layer.aov.addPixel(id, i, avalue, 1.0);
                    } else {
                        layer.aov.addPixel(id, i, avalue, weight);
                    }
                }
            }
        }

        return layer.buffer.addPixel(id, self.clamp(value.reflection) + value.emission, weight);
    }

    pub fn splatSample(self: *Self, layer: u32, sample: SampleTo, color: Vec4f, bounds: Vec4i) void {
        const clamped = self.clamp(color);

        const pixel = sample.pixel;
        const x = pixel[0];
        const y = pixel[1];

        const pixel_uv = sample.pixel_uv;
        const ox = pixel_uv[0] - 0.5;
        const oy = pixel_uv[1] - 0.5;

        if (0 == self.filter_radius_int) {
            const d = self.dimensions;
            const i: u32 = @intCast(d[0] * pixel[1] + pixel[0]);

            self.layers[layer].buffer.splatPixelAtomic(i, clamped, 1.0);
        } else if (1 == self.filter_radius_int) {
            const wx0 = self.eval(ox + 1.0);
            const wx1 = self.eval(ox);
            const wx2 = self.eval(ox - 1.0);

            const wy0 = self.eval(oy + 1.0);
            const wy1 = self.eval(oy);
            const wy2 = self.eval(oy - 1.0);

            // 1. row
            self.splat(layer, .{ x - 1, y - 1 }, wx0 * wy0, clamped, bounds);
            self.splat(layer, .{ x, y - 1 }, wx1 * wy0, clamped, bounds);
            self.splat(layer, .{ x + 1, y - 1 }, wx2 * wy0, clamped, bounds);

            // 2. row
            self.splat(layer, .{ x - 1, y }, wx0 * wy1, clamped, bounds);
            self.splat(layer, .{ x, y }, wx1 * wy1, clamped, bounds);
            self.splat(layer, .{ x + 1, y }, wx2 * wy1, clamped, bounds);

            // 3. row
            self.splat(layer, .{ x - 1, y + 1 }, wx0 * wy2, clamped, bounds);
            self.splat(layer, .{ x, y + 1 }, wx1 * wy2, clamped, bounds);
            self.splat(layer, .{ x + 1, y + 1 }, wx2 * wy2, clamped, bounds);
        } else if (2 == self.filter_radius_int) {
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
            self.splat(layer, .{ x - 2, y - 2 }, wx0 * wy0, clamped, bounds);
            self.splat(layer, .{ x - 1, y - 2 }, wx1 * wy0, clamped, bounds);
            self.splat(layer, .{ x, y - 2 }, wx2 * wy0, clamped, bounds);
            self.splat(layer, .{ x + 1, y - 2 }, wx3 * wy0, clamped, bounds);
            self.splat(layer, .{ x + 2, y - 2 }, wx4 * wy0, clamped, bounds);

            // 2. row
            self.splat(layer, .{ x - 2, y - 1 }, wx0 * wy1, clamped, bounds);
            self.splat(layer, .{ x - 1, y - 1 }, wx1 * wy1, clamped, bounds);
            self.splat(layer, .{ x, y - 1 }, wx2 * wy1, clamped, bounds);
            self.splat(layer, .{ x + 1, y - 1 }, wx3 * wy1, clamped, bounds);
            self.splat(layer, .{ x + 2, y - 1 }, wx4 * wy1, clamped, bounds);

            // 3. row
            self.splat(layer, .{ x - 2, y }, wx0 * wy2, clamped, bounds);
            self.splat(layer, .{ x - 1, y }, wx1 * wy2, clamped, bounds);
            self.splat(layer, .{ x, y }, wx2 * wy2, clamped, bounds);
            self.splat(layer, .{ x + 1, y }, wx3 * wy2, clamped, bounds);
            self.splat(layer, .{ x + 2, y }, wx4 * wy2, clamped, bounds);

            // 4. row
            self.splat(layer, .{ x - 2, y + 1 }, wx0 * wy3, clamped, bounds);
            self.splat(layer, .{ x - 1, y + 1 }, wx1 * wy3, clamped, bounds);
            self.splat(layer, .{ x, y + 1 }, wx2 * wy3, clamped, bounds);
            self.splat(layer, .{ x + 1, y + 1 }, wx3 * wy3, clamped, bounds);
            self.splat(layer, .{ x + 2, y + 1 }, wx4 * wy3, clamped, bounds);

            // 5. row
            self.splat(layer, .{ x - 2, y + 2 }, wx0 * wy4, clamped, bounds);
            self.splat(layer, .{ x - 1, y + 2 }, wx1 * wy4, clamped, bounds);
            self.splat(layer, .{ x, y + 2 }, wx2 * wy4, clamped, bounds);
            self.splat(layer, .{ x + 1, y + 2 }, wx3 * wy4, clamped, bounds);
            self.splat(layer, .{ x + 2, y + 2 }, wx4 * wy4, clamped, bounds);
        }
    }

    pub fn writeTileNoise(self: *Sensor, layer_id: u32, tile: Vec4i, noise: f32) void {
        const layer = &self.layers[layer_id];

        if (0 == layer.aov_noise_buffer.len) {
            return;
        }

        const d = self.dimensions;

        var y: i32 = tile[1];

        while (y <= tile[3]) : (y += 1) {
            var x: i32 = tile[0];
            while (x <= tile[2]) : (x += 1) {
                const id: u32 = @intCast(d[0] * y + x);
                layer.aov_noise_buffer[id] = noise;
            }
        }
    }

    pub fn resolve(self: *const Sensor, layer: u32, target: [*]Pack4f, num_pixels: u32, threads: *Threads) void {
        var context = ResolveContext{ .sensor = self, .target = target, .layer = layer, .aov = .Albedo };
        _ = threads.runRange(&context, ResolveContext.resolve, 0, num_pixels, @sizeOf(Vec4f));
    }

    pub fn resolveTonemap(self: *const Sensor, layer: u32, target: [*]Pack4f, num_pixels: u32, threads: *Threads) void {
        var context = ResolveContext{ .sensor = self, .target = target, .layer = layer, .aov = .Albedo };
        _ = threads.runRange(&context, ResolveContext.resolveTonemap, 0, num_pixels, @sizeOf(Vec4f));
    }

    pub fn resolveAccumulateTonemap(self: *const Sensor, layer: u32, target: [*]Pack4f, num_pixels: u32, threads: *Threads) void {
        var context = ResolveContext{ .sensor = self, .target = target, .layer = layer, .aov = .Albedo };
        _ = threads.runRange(&context, ResolveContext.resolveAccumulateTonemap, 0, num_pixels, @sizeOf(Vec4f));
    }

    pub fn resolveAov(self: *const Sensor, layer: u32, class: AovValue.Class, target: [*]Pack4f, num_pixels: u32, threads: *Threads) void {
        var context = ResolveContext{ .sensor = self, .target = target, .layer = layer, .aov = class };
        _ = threads.runRange(&context, ResolveContext.resolveAov, 0, num_pixels, @sizeOf(Vec4f));
    }

    const ResolveContext = struct {
        sensor: *const Sensor,
        target: [*]Pack4f,
        layer: u32,
        aov: AovValue.Class,

        pub fn resolve(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @as(*const ResolveContext, @ptrCast(context));
            const target = self.target;
            const layer = self.layer;

            self.sensor.layers[layer].buffer.resolve(target, begin, end);
        }

        pub fn resolveTonemap(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @as(*const ResolveContext, @ptrCast(context));
            const target = self.target;
            const layer = self.layer;

            self.sensor.layers[layer].buffer.resolveTonemap(self.sensor.tonemapper, target, begin, end);
        }

        pub fn resolveAccumulateTonemap(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @as(*const ResolveContext, @ptrCast(context));
            const target = self.target;
            const layer = self.layer;

            self.sensor.layers[layer].buffer.resolveAccumulateTonemap(self.sensor.tonemapper, target, begin, end);
        }

        pub fn resolveAov(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @as(*const ResolveContext, @ptrCast(context));
            const target = self.target;
            const class = self.aov;
            const layer = self.layer;

            self.sensor.layers[layer].aov.resolve(class, target, begin, end);
        }
    };

    pub fn isolatedTile(self: *const Self, tile: Vec4i) Vec4i {
        const r = self.filter_radius_int;
        return tile + Vec4i{ r, r, -r, -r };
    }

    fn splat(self: *Self, layer: u32, pixel: Vec2i, weight: f32, color: Vec4f, bounds: Vec4i) void {
        if (@as(u32, @bitCast(pixel[0] - bounds[0])) <= @as(u32, @bitCast(bounds[2])) and
            @as(u32, @bitCast(pixel[1] - bounds[1])) <= @as(u32, @bitCast(bounds[3])))
        {
            const d = self.dimensions;
            const i: u32 = @intCast(d[0] * pixel[1] + pixel[0]);
            self.layers[layer].buffer.splatPixelAtomic(i, color, weight);
        }
    }

    fn add(self: *Self, layer: u32, pixel: Vec2i, weight: f32, color: Vec4f, bounds: Vec4i, isolated: Vec4i) void {
        if (@as(u32, @bitCast(pixel[0] - bounds[0])) <= @as(u32, @bitCast(bounds[2])) and
            @as(u32, @bitCast(pixel[1] - bounds[1])) <= @as(u32, @bitCast(bounds[3])))
        {
            const d = self.dimensions;
            const i: u32 = @intCast(d[0] * pixel[1] + pixel[0]);

            if (@as(u32, @bitCast(pixel[0] - isolated[0])) <= @as(u32, @bitCast(isolated[2])) and
                @as(u32, @bitCast(pixel[1] - isolated[1])) <= @as(u32, @bitCast(isolated[3])))
            {
                self.layers[layer].buffer.addPixel(i, color, weight);
            } else {
                self.layers[layer].buffer.addPixelAtomic(i, color, weight);
            }
        }
    }

    fn addAov(self: *Self, layer: u32, pixel: Vec2i, slot: u32, weight: f32, value: Vec4f, bounds: Vec4i, isolated: Vec4i) void {
        if (@as(u32, @bitCast(pixel[0] - bounds[0])) <= @as(u32, @bitCast(bounds[2])) and
            @as(u32, @bitCast(pixel[1] - bounds[1])) <= @as(u32, @bitCast(bounds[3])))
        {
            const d = self.dimensions;
            const i: u32 = @intCast(d[0] * pixel[1] + pixel[0]);

            if (@as(u32, @bitCast(pixel[0] - isolated[0])) <= @as(u32, @bitCast(isolated[2])) and
                @as(u32, @bitCast(pixel[1] - isolated[1])) <= @as(u32, @bitCast(isolated[3])))
            {
                self.layers[layer].aov.addPixel(i, slot, value, weight);
            } else {
                self.layers[layer].aov.addPixelAtomic(i, slot, value, weight);
            }
        }
    }

    fn lessAov(self: *Self, layer: u32, pixel: Vec2i, slot: u32, value: f32, bounds: Vec4i) void {
        if (@as(u32, @bitCast(pixel[0] - bounds[0])) <= @as(u32, @bitCast(bounds[2])) and
            @as(u32, @bitCast(pixel[1] - bounds[1])) <= @as(u32, @bitCast(bounds[3])))
        {
            const d = self.dimensions;
            const i: u32 = @intCast(d[0] * pixel[1] + pixel[0]);

            self.layers[layer].aov.lessPixel(i, slot, value);
        }
    }

    fn overwriteAov(self: *Self, layer: u32, pixel: Vec2i, slot: u32, weight: f32, value: f32, bounds: Vec4i) void {
        if (@as(u32, @bitCast(pixel[0] - bounds[0])) <= @as(u32, @bitCast(bounds[2])) and
            @as(u32, @bitCast(pixel[1] - bounds[1])) <= @as(u32, @bitCast(bounds[3])))
        {
            const d = self.dimensions;
            const i: u32 = @intCast(d[0] * pixel[1] + pixel[0]);

            self.layers[layer].aov.overwritePixel(i, slot, value, weight);
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

    fn eval(self: *const Self, s: f32) f32 {
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
