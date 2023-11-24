const FFMPEG = @import("ffmpeg.zig").FFMPEG;
const ImageSequence = @import("image_sequence.zig").ImageSequence;
const img = @import("../image/image.zig");
const Float4 = img.Float4;
const AovClass = @import("../rendering/sensor/aov/aov_value.zig").Value.Class;

const base = @import("base");
const Vec4i = base.math.Vec4i;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Sink = union(enum) {
    FFMPEG: FFMPEG,
    ImageSequence: ImageSequence,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        switch (self.*) {
            .FFMPEG => |*s| s.deinit(alloc),
            .ImageSequence => |*s| s.deinit(alloc),
        }
    }

    pub fn write(
        self: *Self,
        alloc: Allocator,
        image: Float4,
        crop: Vec4i,
        aov: ?AovClass,
        camera: u32,
        frame: u32,
        threads: *Threads,
    ) !void {
        switch (self.*) {
            .FFMPEG => |*s| try s.write(alloc, image, camera, threads),
            .ImageSequence => |*s| try s.write(alloc, image, crop, aov, camera, frame, threads),
        }
    }
};
