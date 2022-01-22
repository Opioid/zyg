const Unfiltered = @import("unfiltered.zig").Unfiltered;
const filtered = @import("filtered.zig");
const Opaque = @import("opaque.zig").Opaque;
const Transparent = @import("transparent.zig").Transparent;
const Base = @import("base.zig").Base;

pub const Unfiltered_opaque = Unfiltered(Opaque);
pub const Unfiltered_transparent = Unfiltered(Transparent);

pub const Filtered_1p0_opaque = filtered.Filtered_1p0(Opaque);
pub const Filtered_2p0_opaque = filtered.Filtered_2p0(Opaque);
pub const Filtered_1p0_transparent = filtered.Filtered_1p0(Transparent);
pub const Filtered_2p0_transparent = filtered.Filtered_2p0(Transparent);

const cs = @import("../../sampler/camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const Float4 = @import("../../image/image.zig").Float4;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Sensor = union(enum) {
    Unfiltered_opaque: Unfiltered(Opaque),
    Unfiltered_transparent: Unfiltered(Transparent),
    Filtered_1p0_opaque: Filtered_1p0_opaque,
    Filtered_2p0_opaque: Filtered_2p0_opaque,
    Filtered_1p0_transparent: Filtered_1p0_transparent,
    Filtered_2p0_transparent: Filtered_2p0_transparent,

    pub fn deinit(self: *Sensor, alloc: Allocator) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.deinit(alloc),
            .Unfiltered_transparent => |*s| s.sensor.deinit(alloc),
            .Filtered_1p0_opaque => |*s| s.base.sensor.deinit(alloc),
            .Filtered_2p0_opaque => |*s| s.base.sensor.deinit(alloc),
            .Filtered_1p0_transparent => |*s| s.base.sensor.deinit(alloc),
            .Filtered_2p0_transparent => |*s| s.base.sensor.deinit(alloc),
        }
    }

    pub fn resize(self: *Sensor, alloc: Allocator, dimensions: Vec2i) !void {
        try switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.resize(alloc, dimensions),
            .Unfiltered_transparent => |*s| s.sensor.resize(alloc, dimensions),
            .Filtered_1p0_opaque => |*s| s.base.sensor.resize(alloc, dimensions),
            .Filtered_2p0_opaque => |*s| s.base.sensor.resize(alloc, dimensions),
            .Filtered_1p0_transparent => |*s| s.base.sensor.resize(alloc, dimensions),
            .Filtered_2p0_transparent => |*s| s.base.sensor.resize(alloc, dimensions),
        };
    }

    pub fn base(self: *Sensor) *Base {
        return switch (self.*) {
            .Unfiltered_opaque => |*s| &s.sensor.base,
            .Unfiltered_transparent => |*s| &s.sensor.base,
            .Filtered_1p0_opaque => |*s| &s.base.sensor.base,
            .Filtered_2p0_opaque => |*s| &s.base.sensor.base,
            .Filtered_1p0_transparent => |*s| &s.base.sensor.base,
            .Filtered_2p0_transparent => |*s| &s.base.sensor.base,
        };
    }

    pub fn clear(self: *Sensor, weight: f32) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.clear(weight),
            .Unfiltered_transparent => |*s| s.sensor.clear(weight),
            .Filtered_1p0_opaque => |*s| s.base.sensor.clear(weight),
            .Filtered_2p0_opaque => |*s| s.base.sensor.clear(weight),
            .Filtered_1p0_transparent => |*s| s.base.sensor.clear(weight),
            .Filtered_2p0_transparent => |*s| s.base.sensor.clear(weight),
        }
    }

    pub fn fixZeroWeights(self: *Sensor) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.fixZeroWeights(),
            .Unfiltered_transparent => |*s| s.sensor.fixZeroWeights(),
            .Filtered_1p0_opaque => |*s| s.base.sensor.fixZeroWeights(),
            .Filtered_2p0_opaque => |*s| s.base.sensor.fixZeroWeights(),
            .Filtered_1p0_transparent => |*s| s.base.sensor.fixZeroWeights(),
            .Filtered_2p0_transparent => |*s| s.base.sensor.fixZeroWeights(),
        }
    }

    pub fn mean(self: Sensor, pixel: Vec2i) Vec4f {
        return switch (self) {
            .Unfiltered_opaque => |s| s.sensor.mean(pixel),
            .Unfiltered_transparent => |s| s.sensor.mean(pixel),
            .Filtered_1p0_opaque => |s| s.base.sensor.mean(pixel),
            .Filtered_2p0_opaque => |s| s.base.sensor.mean(pixel),
            .Filtered_1p0_transparent => |s| s.base.sensor.mean(pixel),
            .Filtered_2p0_transparent => |s| s.base.sensor.mean(pixel),
        };
    }

    pub fn addSample(self: *Sensor, sample: Sample, color: Vec4f, offset: Vec2i) Base.Result {
        return switch (self.*) {
            .Unfiltered_opaque => |*s| s.addSample(sample, color, offset),
            .Unfiltered_transparent => |*s| s.addSample(sample, color, offset),
            .Filtered_1p0_opaque => |*s| s.addSample(sample, color, offset),
            .Filtered_2p0_opaque => |*s| s.addSample(sample, color, offset),
            .Filtered_1p0_transparent => |*s| s.addSample(sample, color, offset),
            .Filtered_2p0_transparent => |*s| s.addSample(sample, color, offset),
        };
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

    pub fn resolve(self: Sensor, target: *Float4, threads: *Threads) void {
        const context = ResolveContext{ .sensor = &self, .target = target };

        _ = threads.runRange(&context, ResolveContext.resolve, 0, @intCast(u32, target.description.numPixels()), 16);
    }

    pub fn resolveAccumlate(self: Sensor, target: *Float4, threads: *Threads) void {
        const context = ResolveContext{ .sensor = &self, .target = target };

        _ = threads.runRange(&context, ResolveContext.resolveAccumlate, 0, @intCast(u32, target.description.numPixels()), 16);
    }

    const ResolveContext = struct {
        sensor: *const Sensor,
        target: *Float4,

        pub fn resolve(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @intToPtr(*const ResolveContext, context);
            const target = self.target;

            switch (self.sensor.*) {
                .Unfiltered_opaque => |s| s.sensor.resolve(target, begin, end),
                .Unfiltered_transparent => |s| s.sensor.resolve(target, begin, end),
                .Filtered_1p0_opaque => |s| s.base.sensor.resolve(target, begin, end),
                .Filtered_2p0_opaque => |s| s.base.sensor.resolve(target, begin, end),
                .Filtered_1p0_transparent => |s| s.base.sensor.resolve(target, begin, end),
                .Filtered_2p0_transparent => |s| s.base.sensor.resolve(target, begin, end),
            }
        }

        pub fn resolveAccumlate(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @intToPtr(*const ResolveContext, context);
            const target = self.target;

            switch (self.sensor.*) {
                .Unfiltered_opaque => |s| s.sensor.resolveAccumlate(target, begin, end),
                .Unfiltered_transparent => |s| s.sensor.resolveAccumlate(target, begin, end),
                .Filtered_1p0_opaque => |s| s.base.sensor.resolveAccumlate(target, begin, end),
                .Filtered_2p0_opaque => |s| s.base.sensor.resolveAccumlate(target, begin, end),
                .Filtered_1p0_transparent => |s| s.base.sensor.resolveAccumlate(target, begin, end),
                .Filtered_2p0_transparent => |s| s.base.sensor.resolveAccumlate(target, begin, end),
            }
        }
    };

    pub fn copyWeights(self: Sensor, weights: []f32) void {
        switch (self) {
            .Unfiltered_opaque => |s| s.sensor.copyWeights(weights),
            .Unfiltered_transparent => |s| s.sensor.copyWeights(weights),
            .Filtered_1p0_opaque => |s| s.base.sensor.copyWeights(weights),
            .Filtered_2p0_opaque => |s| s.base.sensor.copyWeights(weights),
            .Filtered_1p0_transparent => |s| s.base.sensor.copyWeights(weights),
            .Filtered_2p0_transparent => |s| s.base.sensor.copyWeights(weights),
        }
    }

    pub fn filterRadiusInt(self: Sensor) i32 {
        return switch (self) {
            .Unfiltered_opaque => 0,
            .Unfiltered_transparent => 0,
            .Filtered_1p0_opaque, .Filtered_1p0_transparent => 1,
            .Filtered_2p0_opaque, .Filtered_2p0_transparent => 2,
        };
    }

    pub fn pixelToImageCoordinates(self: Sensor, sample: *Sample) Vec2f {
        return switch (self) {
            .Filtered_1p0_opaque => |s| s.base.pixelToImageCoordinates(sample),
            .Filtered_1p0_transparent => |s| s.base.pixelToImageCoordinates(sample),
            .Filtered_2p0_opaque => |s| s.base.pixelToImageCoordinates(sample),
            .Filtered_2p0_transparent => |s| s.base.pixelToImageCoordinates(sample),
            else => math.vec2iTo2f(sample.pixel) + sample.pixel_uv,
        };
    }

    pub fn alphaTransparency(self: Sensor) bool {
        return switch (self) {
            .Unfiltered_transparent, .Filtered_1p0_transparent, .Filtered_2p0_transparent => true,
            else => false,
        };
    }
};
