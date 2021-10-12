pub const Clamp = @import("clamp.zig").Clamp;

pub const Unfiltered = @import("unfiltered.zig").Unfiltered;
pub const filtered = @import("filtered.zig");
pub const Opaque = @import("opaque.zig").Opaque;
pub const Transparent = @import("transparent.zig").Transparent;

pub const Filtered_1p0_opaque = filtered.Filtered_1p0(Opaque);
pub const Filtered_2p0_opaque = filtered.Filtered_2p0(Opaque);

const Sample = @import("../../sampler/camera_sample.zig").CameraSample;
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

    pub fn deinit(self: *Sensor, alloc: *Allocator) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.deinit(alloc),
            .Unfiltered_transparent => |*s| s.sensor.deinit(alloc),
            .Filtered_1p0_opaque => |*s| s.base.sensor.deinit(alloc),
            .Filtered_2p0_opaque => |*s| s.base.sensor.deinit(alloc),
        }
    }

    pub fn resize(self: *Sensor, alloc: *Allocator, dimensions: Vec2i) !void {
        try switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.resize(alloc, dimensions),
            .Unfiltered_transparent => |*s| s.sensor.resize(alloc, dimensions),
            .Filtered_1p0_opaque => |*s| s.base.sensor.resize(alloc, dimensions),
            .Filtered_2p0_opaque => |*s| s.base.sensor.resize(alloc, dimensions),
        };
    }

    pub fn clear(self: *Sensor, weight: f32) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.clear(weight),
            .Unfiltered_transparent => |*s| s.sensor.clear(weight),
            .Filtered_1p0_opaque => |*s| s.base.sensor.clear(weight),
            .Filtered_2p0_opaque => |*s| s.base.sensor.clear(weight),
        }
    }

    pub fn addSample(self: *Sensor, sample: Sample, color: Vec4f, offset: Vec2i, isolated: Vec4i, bounds: Vec4i) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.addSample(sample, color, offset),
            .Unfiltered_transparent => |*s| s.addSample(sample, color, offset),
            .Filtered_1p0_opaque => |*s| s.addSample(sample, color, offset, isolated, bounds),
            .Filtered_2p0_opaque => |*s| s.addSample(sample, color, offset, isolated, bounds),
        }
    }

    pub fn resolve(self: Sensor, target: *Float4) void {
        switch (self) {
            .Unfiltered_opaque => |s| s.sensor.resolve(target),
            .Unfiltered_transparent => |s| s.sensor.resolve(target),
            .Filtered_1p0_opaque => |s| s.base.sensor.resolve(target),
            .Filtered_2p0_opaque => |s| s.base.sensor.resolve(target),
        }
    }

    pub fn filterRadiusInt(self: Sensor) i32 {
        return switch (self) {
            .Unfiltered_opaque => 0,
            .Unfiltered_transparent => 0,
            .Filtered_1p0_opaque => 1,
            .Filtered_2p0_opaque => 2,
        };
    }

    pub fn alphaTransparency(self: Sensor) bool {
        return switch (self) {
            .Unfiltered_opaque => false,
            .Unfiltered_transparent => true,
            .Filtered_1p0_opaque => false,
            .Filtered_2p0_opaque => false,
        };
    }

    pub fn isolatedTile(self: Sensor, tile: Vec4i) Vec4i {
        const r = self.filterRadiusInt();

        return tile.add4(Vec4i.init4(r, r, -r, -r));
    }
};
