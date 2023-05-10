const Writer = @import("../image/image_writer.zig").Writer;
const img = @import("../image/image.zig");
const Float4 = img.Float4;
const AovClass = @import("../rendering/sensor/aov/aov_value.zig").Value.Class;

const base = @import("base");
const Vec4i = base.math.Vec4i;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ImageSequence = struct {
    writer: Writer,
    alpha: bool,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.writer.deinit(alloc);
    }

    pub fn write(
        self: *Self,
        alloc: Allocator,
        image: Float4,
        crop: Vec4i,
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

        var encoding: Writer.Encoding = undefined;
        if (aov) |a| {
            encoding = a.encoding();
        } else {
            encoding = if (self.alpha) .Color_alpha else .Color;
        }

        var buffered = std.io.bufferedWriter(file.writer());
        try self.writer.write(alloc, buffered.writer(), image, crop, encoding, threads);
        try buffered.flush();
    }

    fn aovExtension(aov: ?AovClass) []const u8 {
        if (aov) |a| {
            return switch (a) {
                .Albedo => "_albedo",
                .Depth => "_depth",
                .MaterialId => "_mat",
                .GeometricNormal => "_ng",
                .ShadingNormal => "_ns",
            };
        }

        return "";
    }
};
