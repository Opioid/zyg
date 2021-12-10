const PNG = @import("encoding/png/writer.zig").Writer;
const RGBE = @import("encoding/rgbe/writer.zig").Writer;

const img = @import("image.zig");
const Float4 = img.Float4;

const base = @import("base");
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Writer = union(enum) {
    PNG: PNG,
    RGBE: RGBE,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: *Allocator) void {
        switch (self.*) {
            .PNG => |*w| w.deinit(alloc),
            else => {},
        }
    }

    pub fn write(
        self: *Self,
        alloc: *Allocator,
        writer: std.fs.File.Writer,
        image: Float4,
        threads: *Threads,
    ) !void {
        switch (self.*) {
            .PNG => |*w| try w.write(alloc, writer, image, threads),
            .RGBE => try RGBE.write(alloc, writer, image),
        }
    }

    pub fn fileExtension(self: Self) []const u8 {
        return switch (self) {
            .PNG => "png",
            .RGBE => "hdr",
        };
    }
};
