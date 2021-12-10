const ImageSequence = @import("image_sequence.zig").ImageSequence;
const img = @import("../image/image.zig");
const Float4 = img.Float4;

const base = @import("base");
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Sink = union(enum) {
    ImageSequence: ImageSequence,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: *Allocator) void {
        switch (self.*) {
            .ImageSequence => |*is| is.deinit(alloc),
        }
    }

    pub fn write(self: *Self, alloc: *Allocator, image: Float4, frame: u32, threads: *Threads) !void {
        switch (self.*) {
            .ImageSequence => |*is| try is.write(alloc, image, frame, threads),
        }
    }
};
