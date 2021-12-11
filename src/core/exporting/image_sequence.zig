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

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.writer.deinit(alloc);
    }

    pub fn write(self: *Self, alloc: Allocator, image: Float4, frame: u32, threads: *Threads) !void {
        var buf: [32]u8 = undefined;
        const filename = try std.fmt.bufPrint(
            &buf,
            "image_{d:0>8}.{s}",
            .{ frame, self.writer.fileExtension() },
        );

        var file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        try self.writer.write(alloc, file.writer(), image, threads);
    }
};
