pub const Unfiltered = @import("unfiltered.zig").Unfiltered;

pub const Opaque = @import("opaque.zig").Opaque;

const Sample = @import("../../sampler/sampler.zig").Camera_sample;

const Float4 = @import("../../image/image.zig").Float4;

const base = @import("base");
const Vec2i = base.math.Vec2i;
const Vec4f = base.math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Sensor = union(enum) {
    Unfiltered_opaque: Unfiltered(Opaque),

    pub fn deinit(self: *Sensor, alloc: *Allocator) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.deinit(alloc),
        }
    }

    pub fn resize(self: *Sensor, alloc: *Allocator, dimensions: Vec2i) !void {
        try switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.resize(alloc, dimensions),
        };
    }

    pub fn clear(self: *Sensor, weight: f32) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.sensor.clear(weight),
        }
    }

    pub fn addSample(self: *Sensor, sample: Sample, color: Vec4f, offset: Vec2i) void {
        switch (self.*) {
            .Unfiltered_opaque => |*s| s.addSample(sample, color, offset),
        }
    }

    pub fn resolve(self: Sensor, target: *Float4) void {
        switch (self) {
            .Unfiltered_opaque => |s| s.sensor.resolve(target),
        }
    }
};
