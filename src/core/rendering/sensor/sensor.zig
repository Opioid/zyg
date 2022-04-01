const Base = @import("base.zig").Base;
const aov = @import("aov/value.zig");

pub const Unfiltered = @import("unfiltered.zig").Unfiltered;
pub const Filtered = @import("filtered.zig").Filtered;
pub const Opaque = @import("opaque.zig").Opaque;
pub const Transparent = @import("transparent.zig").Transparent;

pub const Tonemapper = @import("tonemapper.zig").Tonemapper;

const cs = @import("../../sampler/camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;

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
    Unfiltered_opaque: Unfiltered(Opaque),
    Unfiltered_transparent: Unfiltered(Transparent),
    Filtered_1p0_opaque: Filtered(Opaque, 1),
    Filtered_2p0_opaque: Filtered(Opaque, 2),
    Filtered_1p0_transparent: Filtered(Transparent, 1),
    Filtered_2p0_transparent: Filtered(Transparent, 2),

    pub fn deinit(self: *Sensor, alloc: Allocator) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.deinit(alloc),
            .Unfiltered_transparent => |*s| s.sensor.deinit(alloc),
            .Filtered_1p0_opaque => |*s| s.sensor.deinit(alloc),
            .Filtered_2p0_opaque => |*s| s.sensor.deinit(alloc),
            .Filtered_1p0_transparent => |*s| s.sensor.deinit(alloc),
            .Filtered_2p0_transparent => |*s| s.sensor.deinit(alloc),
        }
    }

    pub fn resize(self: *Sensor, alloc: Allocator, dimensions: Vec2i, factory: aov.Factory) !void {
        try switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.resize(alloc, dimensions, factory),
            .Unfiltered_transparent => |*s| s.sensor.resize(alloc, dimensions, factory),
            .Filtered_1p0_opaque => |*s| s.sensor.resize(alloc, dimensions, factory),
            .Filtered_2p0_opaque => |*s| s.sensor.resize(alloc, dimensions, factory),
            .Filtered_1p0_transparent => |*s| s.sensor.resize(alloc, dimensions, factory),
            .Filtered_2p0_transparent => |*s| s.sensor.resize(alloc, dimensions, factory),
        };
    }

    pub fn basePtr(self: *Sensor) *Base {
        return switch (self.*) {
            .Unfiltered_opaque => |*s| &s.sensor.base,
            .Unfiltered_transparent => |*s| &s.sensor.base,
            .Filtered_1p0_opaque => |*s| &s.sensor.base,
            .Filtered_2p0_opaque => |*s| &s.sensor.base,
            .Filtered_1p0_transparent => |*s| &s.sensor.base,
            .Filtered_2p0_transparent => |*s| &s.sensor.base,
        };
    }

    pub fn clear(self: *Sensor, weight: f32) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.clear(weight),
            .Unfiltered_transparent => |*s| s.sensor.clear(weight),
            .Filtered_1p0_opaque => |*s| s.sensor.clear(weight),
            .Filtered_2p0_opaque => |*s| s.sensor.clear(weight),
            .Filtered_1p0_transparent => |*s| s.sensor.clear(weight),
            .Filtered_2p0_transparent => |*s| s.sensor.clear(weight),
        }
    }

    pub fn fixZeroWeights(self: *Sensor) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.fixZeroWeights(),
            .Unfiltered_transparent => |*s| s.sensor.fixZeroWeights(),
            .Filtered_1p0_opaque => |*s| s.sensor.fixZeroWeights(),
            .Filtered_2p0_opaque => |*s| s.sensor.fixZeroWeights(),
            .Filtered_1p0_transparent => |*s| s.sensor.fixZeroWeights(),
            .Filtered_2p0_transparent => |*s| s.sensor.fixZeroWeights(),
        }
    }

    pub fn addSample(
        self: *Sensor,
        sample: Sample,
        color: Vec4f,
        aovs: aov.Value,
        offset: Vec2i,
        bounds: Vec4i,
        isolated: Vec4i,
    ) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.addSample(sample, color, aovs, offset),
            .Unfiltered_transparent => |*s| s.addSample(sample, color, aovs, offset),
            .Filtered_1p0_opaque => |*s| s.addSample(sample, color, aovs, offset, bounds, isolated),
            .Filtered_2p0_opaque => |*s| s.addSample(sample, color, aovs, offset, bounds, isolated),
            .Filtered_1p0_transparent => |*s| s.addSample(sample, color, aovs, offset, bounds, isolated),
            .Filtered_2p0_transparent => |*s| s.addSample(sample, color, aovs, offset, bounds, isolated),
        }
    }

    pub fn splatSample(self: *Sensor, sample: SampleTo, color: Vec4f, offset: Vec2i, bounds: Vec4i) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.splatSample(sample, color, offset),
            .Unfiltered_transparent => |*s| s.splatSample(sample, color, offset),
            .Filtered_1p0_opaque => |*s| s.splatSample(sample, color, offset, bounds),
            .Filtered_2p0_opaque => |*s| s.splatSample(sample, color, offset, bounds),
            .Filtered_1p0_transparent => |*s| s.splatSample(sample, color, offset, bounds),
            .Filtered_2p0_transparent => |*s| s.splatSample(sample, color, offset, bounds),
        }
    }

    pub fn resolve(self: Sensor, target: [*]Pack4f, num_pixels: u32, threads: *Threads) void {
        const context = ResolveContext{ .sensor = &self, .target = target, .aov = .Albedo };
        _ = threads.runRange(&context, ResolveContext.resolve, 0, num_pixels, @sizeOf(Vec4f));
    }

    pub fn resolveTonemap(self: Sensor, target: [*]Pack4f, num_pixels: u32, threads: *Threads) void {
        const context = ResolveContext{ .sensor = &self, .target = target, .aov = .Albedo };
        _ = threads.runRange(&context, ResolveContext.resolveTonemap, 0, num_pixels, @sizeOf(Vec4f));
    }

    pub fn resolveAccumulateTonemap(self: Sensor, target: [*]Pack4f, num_pixels: u32, threads: *Threads) void {
        const context = ResolveContext{ .sensor = &self, .target = target, .aov = .Albedo };
        _ = threads.runRange(&context, ResolveContext.resolveAccumulateTonemap, 0, num_pixels, @sizeOf(Vec4f));
    }

    pub fn resolveAov(self: Sensor, class: aov.Value.Class, target: [*]Pack4f, num_pixels: u32, threads: *Threads) void {
        const context = ResolveContext{ .sensor = &self, .target = target, .aov = class };
        _ = threads.runRange(&context, ResolveContext.resolveAov, 0, num_pixels, @sizeOf(Vec4f));
    }

    const ResolveContext = struct {
        sensor: *const Sensor,
        target: [*]Pack4f,
        aov: aov.Value.Class,

        pub fn resolve(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @intToPtr(*const ResolveContext, context);
            const target = self.target;

            switch (self.sensor.*) {
                .Unfiltered_opaque => |s| s.sensor.resolve(target, begin, end),
                .Unfiltered_transparent => |s| s.sensor.resolve(target, begin, end),
                .Filtered_1p0_opaque => |s| s.sensor.resolve(target, begin, end),
                .Filtered_2p0_opaque => |s| s.sensor.resolve(target, begin, end),
                .Filtered_1p0_transparent => |s| s.sensor.resolve(target, begin, end),
                .Filtered_2p0_transparent => |s| s.sensor.resolve(target, begin, end),
            }
        }

        pub fn resolveTonemap(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @intToPtr(*const ResolveContext, context);
            const target = self.target;

            switch (self.sensor.*) {
                .Unfiltered_opaque => |s| s.sensor.resolveTonemap(target, begin, end),
                .Unfiltered_transparent => |s| s.sensor.resolveTonemap(target, begin, end),
                .Filtered_1p0_opaque => |s| s.sensor.resolveTonemap(target, begin, end),
                .Filtered_2p0_opaque => |s| s.sensor.resolveTonemap(target, begin, end),
                .Filtered_1p0_transparent => |s| s.sensor.resolveTonemap(target, begin, end),
                .Filtered_2p0_transparent => |s| s.sensor.resolveTonemap(target, begin, end),
            }
        }

        pub fn resolveAccumulateTonemap(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @intToPtr(*const ResolveContext, context);
            const target = self.target;

            switch (self.sensor.*) {
                .Unfiltered_opaque => |s| s.sensor.resolveAccumulateTonemap(target, begin, end),
                .Unfiltered_transparent => |s| s.sensor.resolveAccumulateTonemap(target, begin, end),
                .Filtered_1p0_opaque => |s| s.sensor.resolveAccumulateTonemap(target, begin, end),
                .Filtered_2p0_opaque => |s| s.sensor.resolveAccumulateTonemap(target, begin, end),
                .Filtered_1p0_transparent => |s| s.sensor.resolveAccumulateTonemap(target, begin, end),
                .Filtered_2p0_transparent => |s| s.sensor.resolveAccumulateTonemap(target, begin, end),
            }
        }

        pub fn resolveAov(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @intToPtr(*const ResolveContext, context);
            const target = self.target;
            const class = self.aov;

            switch (self.sensor.*) {
                .Unfiltered_opaque => |s| s.sensor.base.aov.resolve(class, target, begin, end),
                .Unfiltered_transparent => |s| s.sensor.base.aov.resolve(class, target, begin, end),
                .Filtered_1p0_opaque => |s| s.sensor.base.aov.resolve(class, target, begin, end),
                .Filtered_2p0_opaque => |s| s.sensor.base.aov.resolve(class, target, begin, end),
                .Filtered_1p0_transparent => |s| s.sensor.base.aov.resolve(class, target, begin, end),
                .Filtered_2p0_transparent => |s| s.sensor.base.aov.resolve(class, target, begin, end),
            }
        }
    };

    pub fn filterRadiusInt(self: Sensor) i32 {
        return switch (self) {
            .Unfiltered_opaque => 0,
            .Unfiltered_transparent => 0,
            .Filtered_1p0_opaque, .Filtered_1p0_transparent => 1,
            .Filtered_2p0_opaque, .Filtered_2p0_transparent => 2,
        };
    }

    pub fn alphaTransparency(self: Sensor) bool {
        return switch (self) {
            .Unfiltered_transparent, .Filtered_1p0_transparent, .Filtered_2p0_transparent => true,
            else => false,
        };
    }

    pub fn isolatedTile(self: Sensor, tile: Vec4i) Vec4i {
        const r = self.filterRadiusInt();

        return tile + Vec4i{ r, r, -r, -r };
    }
};
