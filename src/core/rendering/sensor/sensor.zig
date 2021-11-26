pub const Clamp = @import("clamp.zig").Clamp;

pub const Unfiltered = @import("unfiltered.zig").Unfiltered;
pub const filtered = @import("filtered.zig");
pub const Opaque = @import("opaque.zig").Opaque;
pub const Transparent = @import("transparent.zig").Transparent;

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
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Sensor = union(enum) {
    Unfiltered_opaque: Unfiltered(Opaque),
    Unfiltered_transparent: Unfiltered(Transparent),
    Filtered_1p0_opaque: Filtered_1p0_opaque,
    Filtered_2p0_opaque: Filtered_2p0_opaque,
    Filtered_1p0_transparent: Filtered_1p0_transparent,
    Filtered_2p0_transparent: Filtered_2p0_transparent,

    pub fn deinit(self: *Sensor, alloc: *Allocator) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.deinit(alloc),
            .Unfiltered_transparent => |*s| s.sensor.deinit(alloc),
            .Filtered_1p0_opaque => |*s| s.base.sensor.deinit(alloc),
            .Filtered_2p0_opaque => |*s| s.base.sensor.deinit(alloc),
            .Filtered_1p0_transparent => |*s| s.base.sensor.deinit(alloc),
            .Filtered_2p0_transparent => |*s| s.base.sensor.deinit(alloc),
        }
    }

    pub fn resize(self: *Sensor, alloc: *Allocator, dimensions: Vec2i) !void {
        try switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.resize(alloc, dimensions),
            .Unfiltered_transparent => |*s| s.sensor.resize(alloc, dimensions),
            .Filtered_1p0_opaque => |*s| s.base.sensor.resize(alloc, dimensions),
            .Filtered_2p0_opaque => |*s| s.base.sensor.resize(alloc, dimensions),
            .Filtered_1p0_transparent => |*s| s.base.sensor.resize(alloc, dimensions),
            .Filtered_2p0_transparent => |*s| s.base.sensor.resize(alloc, dimensions),
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

    pub fn addSample(self: *Sensor, sample: Sample, color: Vec4f, offset: Vec2i, bounds: Vec4i, isolated: Vec4i) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.addSample(sample, color, offset),
            .Unfiltered_transparent => |*s| s.addSample(sample, color, offset),
            .Filtered_1p0_opaque => |*s| s.addSample(sample, color, offset, bounds, isolated),
            .Filtered_2p0_opaque => |*s| s.addSample(sample, color, offset, bounds, isolated),
            .Filtered_1p0_transparent => |*s| s.addSample(sample, color, offset, bounds, isolated),
            .Filtered_2p0_transparent => |*s| s.addSample(sample, color, offset, bounds, isolated),
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

    pub fn resolve(self: Sensor, target: *Float4) void {
        switch (self) {
            .Unfiltered_opaque => |s| s.sensor.resolve(target),
            .Unfiltered_transparent => |s| s.sensor.resolve(target),
            .Filtered_1p0_opaque => |s| s.base.sensor.resolve(target),
            .Filtered_2p0_opaque => |s| s.base.sensor.resolve(target),
            .Filtered_1p0_transparent => |s| s.base.sensor.resolve(target),
            .Filtered_2p0_transparent => |s| s.base.sensor.resolve(target),
        }
    }

    pub fn resolveAccumlate(self: Sensor, target: *Float4) void {
        switch (self) {
            .Unfiltered_opaque => |s| s.sensor.resolveAccumlate(target),
            .Unfiltered_transparent => |s| s.sensor.resolveAccumlate(target),
            .Filtered_1p0_opaque => |s| s.base.sensor.resolveAccumlate(target),
            .Filtered_2p0_opaque => |s| s.base.sensor.resolveAccumlate(target),
            .Filtered_1p0_transparent => |s| s.base.sensor.resolveAccumlate(target),
            .Filtered_2p0_transparent => |s| s.base.sensor.resolveAccumlate(target),
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
