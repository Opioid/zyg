const Tonemapper = @import("tonemapping/tonemapper.zig").Tonemapper;
const Sensor = @import("../sensor/sensor.zig").Sensor;
const cam = @import("../../camera/perspective.zig");
const img = @import("../../image/image.zig");
const base = @import("base");
usingnamespace base;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Pipeline = struct {
    tonemapper: Tonemapper = .{ .Linear = .{} },

    scratch: img.Float4 = .{},

    pub fn deinit(self: *Pipeline, alloc: *Allocator) void {
        self.scratch.deinit(alloc);
    }

    pub fn configure(self: *Pipeline, alloc: *Allocator, camera: cam.Perspective) !void {
        try self.scratch.resize(alloc, img.Description.init2D(camera.sensorDimensions()));
    }

    pub fn apply(self: *Pipeline, sensor: Sensor, destination: *img.Float4, threads: *thread.Pool) void {
        sensor.resolve(&self.scratch);

        self.tonemapper.apply(&self.scratch, destination, threads);
    }
};
