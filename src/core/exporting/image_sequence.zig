const Writer = @import("../image/writer.zig").Writer;
const img = @import("../image/image.zig");
const Float4 = img.Float4;
const AovClass = @import("../rendering/sensor/aov/value.zig").Value.Class;

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

    pub fn write(
        self: *Self,
        alloc: Allocator,
        image: Float4,
        aov: ?AovClass,
        frame: u32,
        threads: *Threads,
    ) !void {
        var buf: [40]u8 = undefined;
        const filename = try std.fmt.bufPrint(
            &buf,
            "image_{d:0>8}{s}.{s}",
            .{ frame, aovExtension(aov), self.writer.fileExtension() },
        );

        var file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        var buffered = std.io.bufferedWriter(file.writer());
        try self.writer.write(alloc, buffered.writer(), image, aov, threads);
        try buffered.flush();
    }

    fn aovExtension(aov: ?AovClass) []const u8 {
        if (aov) |a| {
            return switch (a) {
                .Albedo => "_albedo",
                .Depth => "_depth",
                .MaterialId => "_mat",
                .ShadingNormal => "_n",
            };
        }

        return "";
    }
};
