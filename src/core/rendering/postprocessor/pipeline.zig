const tm = @import("tonemapping/tonemapper.zig");
const Sensor = @import("../sensor/sensor.zig").Sensor;
const cam = @import("../../camera/perspective.zig");
const img = @import("../../image/image.zig");
const base = @import("base");
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Pipeline = struct {
    tonemapper: tm.Tonemapper = .{ .Linear = tm.Linear.init(0.0) },

    scratch: img.Float4 = .{},

    pub fn deinit(self: *Pipeline, alloc: Allocator) void {
        self.scratch.deinit(alloc);
    }

    pub fn configure(self: *Pipeline, alloc: Allocator, camera: cam.Perspective) !void {
        try self.scratch.resize(alloc, img.Description.init2D(camera.sensorDimensions()));
    }

    pub fn seed(self: *Pipeline, sensor: Sensor, destination: *img.Float4, threads: *Threads) void {
        sensor.resolve(&self.scratch, threads);

        _ = destination;
    }

    pub fn apply(self: *Pipeline, sensor: Sensor, destination: *img.Float4, threads: *Threads) void {
        sensor.resolve(&self.scratch, threads);

        self.tonemapper.apply(&self.scratch, destination, threads);
    }

    pub fn applyAccumulate(self: *Pipeline, sensor: Sensor, destination: *img.Float4, threads: *Threads) void {
        sensor.resolveAccumlate(&self.scratch, threads);

        self.tonemapper.apply(&self.scratch, destination, threads);
    }
};
