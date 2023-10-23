const aov = @import("aov/aov_value.zig");

pub const Filtered = @import("filtered.zig").Filtered;
pub const Opaque = @import("opaque.zig").Opaque;
pub const Transparent = @import("transparent.zig").Transparent;

pub const Tonemapper = @import("tonemapper.zig").Tonemapper;

const cs = @import("../../camera/camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const Sampler = @import("../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
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

pub const Sensor = union(enum) {
    Opaque: Filtered(Opaque),
    Transparent: Filtered(Transparent),

    pub fn deinit(self: *Sensor, alloc: Allocator) void {
        switch (self.*) {
            inline else => |*s| s.deinit(alloc),
        }
    }

    pub fn resize(self: *Sensor, alloc: Allocator, dimensions: Vec2i, factory: aov.Factory) !void {
        try switch (self.*) {
            inline else => |*s| s.resize(alloc, dimensions, factory),
        };
    }

    pub fn cameraSample(self: *Sensor, pixel: Vec2i, sampler: *Sampler) Sample {
        return switch (self.*) {
            inline else => |*s| s.cameraSample(pixel, sampler),
        };
    }

    pub fn setTonemapper(self: *Sensor, tonemapper: Tonemapper) void {
        switch (self.*) {
            inline else => |*s| s.tonemapper = tonemapper,
        }
    }

    pub fn clear(self: *Sensor, weight: f32) void {
        switch (self.*) {
            inline else => |*s| s.sensor.clear(weight),
        }
    }

    pub fn clearAov(self: *Sensor) void {
        switch (self.*) {
            inline else => |*s| s.aov.clear(),
        }
    }

    pub fn fixZeroWeights(self: *Sensor) void {
        switch (self.*) {
            inline else => |*s| s.sensor.fixZeroWeights(),
        }
    }

    pub fn addSample(
        self: *Sensor,
        sample: Sample,
        color: Vec4f,
        aovs: aov.Value,
        bounds: Vec4i,
        isolated: Vec4i,
    ) void {
        switch (self.*) {
            inline else => |*s| s.addSample(sample, color, aovs, bounds, isolated),
        }
    }

    pub fn splatSample(self: *Sensor, sample: SampleTo, color: Vec4f, bounds: Vec4i) void {
        switch (self.*) {
            inline else => |*s| s.splatSample(sample, color, bounds),
        }
    }

    pub fn resolve(self: *const Sensor, target: [*]Pack4f, num_pixels: u32, threads: *Threads) void {
        var context = ResolveContext{ .sensor = self, .target = target, .aov = .Albedo };
        _ = threads.runRange(&context, ResolveContext.resolve, 0, num_pixels, @sizeOf(Vec4f));
    }

    pub fn resolveTonemap(self: *const Sensor, target: [*]Pack4f, num_pixels: u32, threads: *Threads) void {
        var context = ResolveContext{ .sensor = self, .target = target, .aov = .Albedo };
        _ = threads.runRange(&context, ResolveContext.resolveTonemap, 0, num_pixels, @sizeOf(Vec4f));
    }

    pub fn resolveAccumulateTonemap(self: *const Sensor, target: [*]Pack4f, num_pixels: u32, threads: *Threads) void {
        var context = ResolveContext{ .sensor = self, .target = target, .aov = .Albedo };
        _ = threads.runRange(&context, ResolveContext.resolveAccumulateTonemap, 0, num_pixels, @sizeOf(Vec4f));
    }

    pub fn resolveAov(self: *const Sensor, class: aov.Value.Class, target: [*]Pack4f, num_pixels: u32, threads: *Threads) void {
        var context = ResolveContext{ .sensor = self, .target = target, .aov = class };
        _ = threads.runRange(&context, ResolveContext.resolveAov, 0, num_pixels, @sizeOf(Vec4f));
    }

    const ResolveContext = struct {
        sensor: *const Sensor,
        target: [*]Pack4f,
        aov: aov.Value.Class,

        pub fn resolve(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @as(*const ResolveContext, @ptrCast(context));
            const target = self.target;

            switch (self.sensor.*) {
                inline else => |*s| s.sensor.resolve(target, begin, end),
            }
        }

        pub fn resolveTonemap(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @as(*const ResolveContext, @ptrCast(context));
            const target = self.target;

            switch (self.sensor.*) {
                inline else => |*s| s.sensor.resolveTonemap(s.tonemapper, target, begin, end),
            }
        }

        pub fn resolveAccumulateTonemap(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @as(*const ResolveContext, @ptrCast(context));
            const target = self.target;

            switch (self.sensor.*) {
                inline else => |*s| s.sensor.resolveAccumulateTonemap(s.tonemapper, target, begin, end),
            }
        }

        pub fn resolveAov(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @as(*const ResolveContext, @ptrCast(context));
            const target = self.target;
            const class = self.aov;

            switch (self.sensor.*) {
                inline else => |*s| s.aov.resolve(class, target, begin, end),
            }
        }
    };

    pub fn filterRadiusInt(self: *const Sensor) i32 {
        return switch (self.*) {
            inline else => |*s| s.radius_int,
        };
    }

    pub fn alphaTransparency(self: *const Sensor) bool {
        return switch (self.*) {
            .Transparent => true,
            else => false,
        };
    }

    pub fn isolatedTile(self: *const Sensor, tile: Vec4i) Vec4i {
        const r = self.filterRadiusInt();

        return tile + Vec4i{ r, r, -r, -r };
    }
};
