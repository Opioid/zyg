const Writer = @import("../image/writer.zig").Writer;
const img = @import("../image/image.zig");
const Float4 = img.Float4;

const base = @import("base");
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ImageSequence = struct {
    writer: Writer,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: *Allocator) void {
        self.writer.deinit(alloc);
    }

    pub fn write(self: *Self, alloc: *Allocator, image: Float4, frame: u32, threads: *Threads) !void {
        _ = frame;

        var file = try std.fs.cwd().createFile("image.png", .{});
        defer file.close();

        const stream = file.writer();

        try self.writer.write(alloc, stream, image, threads);
    }
};
