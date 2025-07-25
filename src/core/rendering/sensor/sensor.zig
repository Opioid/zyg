const AovBuffer = @import("aov/aov_buffer.zig").Buffer;
const aovns = @import("aov/aov_value.zig");
const AovValue = aovns.Value;
const AovFactory = aovns.Factory;

const cs = @import("../../camera/camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const IValue = @import("../integrator/helper.zig").IValue;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Pack4f = math.Pack4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Sensor = struct {
    pub const Buffer = @import("buffer.zig").Buffer;
    pub const Tonemapper = @import("tonemapper.zig").Tonemapper;

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

    const Func = math.ifunc.InterpolatedFunction1DN(30);

    const Layer = struct {
        buffer: Buffer,
        aov: AovBuffer,

        fn deinit(self: *Layer, alloc: Allocator) void {
            self.buffer.deinit(alloc);
            self.aov.deinit(alloc);
        }

        fn resize(self: *Layer, alloc: Allocator, len: usize, factory: AovFactory) !void {
            try self.buffer.resize(alloc, len);
            try self.aov.resize(alloc, len, factory);
        }
    };

    class: Buffer.Class,

    layers: []Layer,

    dimensions: Vec2i,

    clamp_max: f32,

    filter_radius_int: i32,

    filter: Func,

    tonemapper: Tonemapper = Tonemapper.init(.Linear, 0.0),

    const Self = @This();

    pub fn init(class: Buffer.Class, clamp_max: f32, radius: f32, f: anytype) Self {
        var result = Self{
            .class = class,
            .layers = &.{},
            .dimensions = @splat(0),
            .clamp_max = clamp_max,
            .filter_radius_int = @intFromFloat(@ceil(radius)),
            .filter = Func.init(0.0, radius, f),
        };

        if (radius > 0.0) {
            result.filter.scale(1.0 / result.integral(64, radius));
        }

        return result;
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        for (self.layers) |*l| {
            l.deinit(alloc);
        }

        alloc.free(self.layers);
    }

    pub fn resize(self: *Self, alloc: Allocator, dimensions: Vec2i, num_layers: u32, factory: AovFactory) !void {
        self.dimensions = dimensions;

        const len: usize = @intCast(dimensions[0] * dimensions[1]);

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

        for (self.layers[0..num_layers]) |*l| {
            try l.resize(alloc, len, factory);
        }
    }

    pub fn cameraSample(self: *Self, pixel: Vec2i, sampler: *Sampler) Sample {
        _ = self;

        const s4 = sampler.sample4D();
        const s1 = sampler.sample1D();

        sampler.incrementPadding();

        return .{
            .pixel = pixel,
            .pixel_uv = .{ s4[0], s4[1] },
            .lens_uv = .{ s4[2], s4[3] },
            .time = s1,
        };
    }

    pub fn addSample(
        self: *Sensor,
        layer: u32,
        sample: Sample,
        value: IValue,
        aov: AovValue,
        bounds: Vec4i,
        isolated: Vec4i,
    ) void {
        const indirect = self.clamp(value.indirect);
        const summed = indirect + value.direct;
        const composed = Vec4f{ summed[0], summed[1], summed[2], value.direct[3] };

        const pixel = sample.pixel;
        const x = pixel[0];
        const y = pixel[1];

        const pixel_uv = sample.pixel_uv;
        const ox = pixel_uv[0] - 0.5;
        const oy = pixel_uv[1] - 0.5;

        if (0 == self.filter_radius_int) {
            const d = self.dimensions;
            const id: u32 = @intCast(d[0] * pixel[1] + pixel[0]);

            self.layers[layer].buffer.addPixel(id, composed, 1.0);

            if (aov.active()) {
                const len = AovValue.NumClasses;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const class: AovValue.Class = @enumFromInt(i);
                    if (aov.activeClass(class)) {
                        const avalue = switch (class) {
                            .Direct => value.direct,
                            .Indirect => indirect,
                            else => aov.values[i],
                        };

                        if (.Depth == class) {
                            self.layers[layer].aov.lessPixel(id, i, avalue[0]);
                        } else if (.MaterialId == class) {
                            self.layers[layer].aov.overwritePixel(id, i, avalue[0], 1.0);
                        } else {
                            self.layers[layer].aov.addPixel(id, i, avalue, 1.0);
                        }
                    }
                }
            }
        } else if (1 == self.filter_radius_int) {
            const wx0 = self.eval(ox + 1.0);
            const wx1 = self.eval(ox);
            const wx2 = self.eval(ox - 1.0);

            const wy0 = self.eval(oy + 1.0);
            const wy1 = self.eval(oy);
            const wy2 = self.eval(oy - 1.0);

            // 1. row
            self.add(layer, .{ x - 1, y - 1 }, wx0 * wy0, composed, bounds, isolated);
            self.add(layer, .{ x, y - 1 }, wx1 * wy0, composed, bounds, isolated);
            self.add(layer, .{ x + 1, y - 1 }, wx2 * wy0, composed, bounds, isolated);

            // 2. row
            self.add(layer, .{ x - 1, y }, wx0 * wy1, composed, bounds, isolated);
            self.add(layer, .{ x, y }, wx1 * wy1, composed, bounds, isolated);
            self.add(layer, .{ x + 1, y }, wx2 * wy1, composed, bounds, isolated);

            // 3. row
            self.add(layer, .{ x - 1, y + 1 }, wx0 * wy2, composed, bounds, isolated);
            self.add(layer, .{ x, y + 1 }, wx1 * wy2, composed, bounds, isolated);
            self.add(layer, .{ x + 1, y + 1 }, wx2 * wy2, composed, bounds, isolated);

            if (aov.active()) {
                const len = AovValue.NumClasses;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const class: AovValue.Class = @enumFromInt(i);
                    if (aov.activeClass(class)) {
                        const avalue = switch (class) {
                            .Direct => value.direct,
                            .Indirect => indirect,
                            else => aov.values[i],
                        };

                        if (.Depth == class) {
                            self.lessAov(layer, .{ x, y }, i, avalue[0], bounds);
                        } else if (.MaterialId == class) {
                            self.overwriteAov(layer, .{ x, y }, i, wx2 * wy2, avalue[0], bounds);
                        } else {
                            // 1. row
                            self.addAov(layer, .{ x - 1, y - 1 }, i, wx0 * wy0, avalue, bounds, isolated);
                            self.addAov(layer, .{ x, y - 1 }, i, wx1 * wy0, avalue, bounds, isolated);
                            self.addAov(layer, .{ x + 1, y - 1 }, i, wx2 * wy0, avalue, bounds, isolated);

                            // 2. row
                            self.addAov(layer, .{ x - 1, y }, i, wx0 * wy1, avalue, bounds, isolated);
                            self.addAov(layer, .{ x, y }, i, wx1 * wy1, avalue, bounds, isolated);
                            self.addAov(layer, .{ x + 1, y }, i, wx2 * wy1, avalue, bounds, isolated);

                            // 3. row
                            self.addAov(layer, .{ x - 1, y + 1 }, i, wx0 * wy2, avalue, bounds, isolated);
                            self.addAov(layer, .{ x, y + 1 }, i, wx1 * wy2, avalue, bounds, isolated);
                            self.addAov(layer, .{ x + 1, y + 1 }, i, wx2 * wy2, avalue, bounds, isolated);
                        }
                    }
                }
            }
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
            self.add(layer, .{ x - 2, y - 2 }, wx0 * wy0, composed, bounds, isolated);
            self.add(layer, .{ x - 1, y - 2 }, wx1 * wy0, composed, bounds, isolated);
            self.add(layer, .{ x, y - 2 }, wx2 * wy0, composed, bounds, isolated);
            self.add(layer, .{ x + 1, y - 2 }, wx3 * wy0, composed, bounds, isolated);
            self.add(layer, .{ x + 2, y - 2 }, wx4 * wy0, composed, bounds, isolated);

            // 2. row
            self.add(layer, .{ x - 2, y - 1 }, wx0 * wy1, composed, bounds, isolated);
            self.add(layer, .{ x - 1, y - 1 }, wx1 * wy1, composed, bounds, isolated);
            self.add(layer, .{ x, y - 1 }, wx2 * wy1, composed, bounds, isolated);
            self.add(layer, .{ x + 1, y - 1 }, wx3 * wy1, composed, bounds, isolated);
            self.add(layer, .{ x + 2, y - 1 }, wx4 * wy1, composed, bounds, isolated);

            // 3. row
            self.add(layer, .{ x - 2, y }, wx0 * wy2, composed, bounds, isolated);
            self.add(layer, .{ x - 1, y }, wx1 * wy2, composed, bounds, isolated);
            self.add(layer, .{ x, y }, wx2 * wy2, composed, bounds, isolated);
            self.add(layer, .{ x + 1, y }, wx3 * wy2, composed, bounds, isolated);
            self.add(layer, .{ x + 2, y }, wx4 * wy2, composed, bounds, isolated);

            // 4. row
            self.add(layer, .{ x - 2, y + 1 }, wx0 * wy3, composed, bounds, isolated);
            self.add(layer, .{ x - 1, y + 1 }, wx1 * wy3, composed, bounds, isolated);
            self.add(layer, .{ x, y + 1 }, wx2 * wy3, composed, bounds, isolated);
            self.add(layer, .{ x + 1, y + 1 }, wx3 * wy3, composed, bounds, isolated);
            self.add(layer, .{ x + 2, y + 1 }, wx4 * wy3, composed, bounds, isolated);

            // 5. row
            self.add(layer, .{ x - 2, y + 2 }, wx0 * wy4, composed, bounds, isolated);
            self.add(layer, .{ x - 1, y + 2 }, wx1 * wy4, composed, bounds, isolated);
            self.add(layer, .{ x, y + 2 }, wx2 * wy4, composed, bounds, isolated);
            self.add(layer, .{ x + 1, y + 2 }, wx3 * wy4, composed, bounds, isolated);
            self.add(layer, .{ x + 2, y + 2 }, wx4 * wy4, composed, bounds, isolated);

            if (aov.active()) {
                const len = AovValue.NumClasses;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const class: AovValue.Class = @enumFromInt(i);
                    if (aov.activeClass(class)) {
                        const avalue = switch (class) {
                            .Direct => value.direct,
                            .Indirect => indirect,
                            else => aov.values[i],
                        };

                        if (.Depth == class) {
                            self.lessAov(layer, .{ x, y }, i, avalue[0], bounds);
                        } else if (.MaterialId == class) {
                            self.overwriteAov(layer, .{ x, y }, i, wx2 * wy2, avalue[0], bounds);
                        } else {
                            // 1. row
                            self.addAov(layer, .{ x - 2, y - 2 }, i, wx0 * wy0, avalue, bounds, isolated);
                            self.addAov(layer, .{ x - 1, y - 2 }, i, wx1 * wy0, avalue, bounds, isolated);
                            self.addAov(layer, .{ x, y - 2 }, i, wx2 * wy0, avalue, bounds, isolated);
                            self.addAov(layer, .{ x + 1, y - 2 }, i, wx3 * wy0, avalue, bounds, isolated);
                            self.addAov(layer, .{ x + 2, y - 2 }, i, wx4 * wy0, avalue, bounds, isolated);

                            // 2. row
                            self.addAov(layer, .{ x - 2, y - 1 }, i, wx0 * wy1, avalue, bounds, isolated);
                            self.addAov(layer, .{ x - 1, y - 1 }, i, wx1 * wy1, avalue, bounds, isolated);
                            self.addAov(layer, .{ x, y - 1 }, i, wx2 * wy1, avalue, bounds, isolated);
                            self.addAov(layer, .{ x + 1, y - 1 }, i, wx3 * wy1, avalue, bounds, isolated);
                            self.addAov(layer, .{ x + 2, y - 1 }, i, wx4 * wy1, avalue, bounds, isolated);

                            // 3. row
                            self.addAov(layer, .{ x - 2, y }, i, wx0 * wy2, avalue, bounds, isolated);
                            self.addAov(layer, .{ x - 1, y }, i, wx1 * wy2, avalue, bounds, isolated);
                            self.addAov(layer, .{ x, y }, i, wx2 * wy2, avalue, bounds, isolated);
                            self.addAov(layer, .{ x + 1, y }, i, wx3 * wy2, avalue, bounds, isolated);
                            self.addAov(layer, .{ x + 2, y }, i, wx4 * wy2, avalue, bounds, isolated);

                            // 4. row
                            self.addAov(layer, .{ x - 2, y + 1 }, i, wx0 * wy3, avalue, bounds, isolated);
                            self.addAov(layer, .{ x - 1, y + 1 }, i, wx1 * wy3, avalue, bounds, isolated);
                            self.addAov(layer, .{ x, y + 1 }, i, wx2 * wy3, avalue, bounds, isolated);
                            self.addAov(layer, .{ x + 1, y + 1 }, i, wx3 * wy3, avalue, bounds, isolated);
                            self.addAov(layer, .{ x + 2, y + 1 }, i, wx4 * wy3, avalue, bounds, isolated);

                            // 5. row
                            self.addAov(layer, .{ x - 2, y + 2 }, i, wx0 * wy4, avalue, bounds, isolated);
                            self.addAov(layer, .{ x - 1, y + 2 }, i, wx1 * wy4, avalue, bounds, isolated);
                            self.addAov(layer, .{ x, y + 2 }, i, wx2 * wy4, avalue, bounds, isolated);
                            self.addAov(layer, .{ x + 1, y + 2 }, i, wx3 * wy4, avalue, bounds, isolated);
                            self.addAov(layer, .{ x + 2, y + 2 }, i, wx4 * wy4, avalue, bounds, isolated);
                        }
                    }
                }
            }
        }
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

            const self: *const ResolveContext = @ptrCast(context);
            const target = self.target;
            const layer = self.layer;

            self.sensor.layers[layer].buffer.resolve(target, begin, end);
        }

        pub fn resolveTonemap(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self: *const ResolveContext = @ptrCast(context);
            const target = self.target;
            const layer = self.layer;

            self.sensor.layers[layer].buffer.resolveTonemap(self.sensor.tonemapper, target, begin, end);
        }

        pub fn resolveAccumulateTonemap(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self: *const ResolveContext = @ptrCast(context);
            const target = self.target;
            const layer = self.layer;

            self.sensor.layers[layer].buffer.resolveAccumulateTonemap(self.sensor.tonemapper, target, begin, end);
        }

        pub fn resolveAov(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self: *const ResolveContext = @ptrCast(context);
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
            return @as(Vec4f, @splat(r)) * color;
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
