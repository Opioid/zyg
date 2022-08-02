const EXR = @import("encoding/exr/writer.zig").Writer;
pub const PNG = @import("encoding/png/writer.zig").Writer;
const RGBE = @import("encoding/rgbe/writer.zig").Writer;

const img = @import("image.zig");
const Float4 = img.Float4;
const AovClass = @import("../rendering/sensor/aov/value.zig").Value.Class;

const base = @import("base");
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Writer = union(enum) {
    pub const Encoding = enum {
        Color,
        Color_alpha,
        Normal,
        Depth,
        ID,
        Float,
    };

    pub const ExrWriter = EXR;
    pub const PngWriter = PNG;
    pub const RgbeWriter = RGBE;

    EXR: EXR,
    PNG: PNG,
    RGBE: RGBE,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        switch (self.*) {
            .PNG => |*w| w.deinit(alloc),
            else => {},
        }
    }

    pub fn write(
        self: *Self,
        alloc: Allocator,
        writer: anytype,
        image: Float4,
        encoding: Encoding,
        threads: *Threads,
    ) !void {
        switch (self.*) {
            .EXR => |w| try w.write(alloc, writer, image, encoding, threads),
            .PNG => |*w| try w.write(alloc, writer, image, encoding, threads),
            .RGBE => try RGBE.write(alloc, writer, image),
        }
    }

    pub fn fileExtension(self: Self) []const u8 {
        return switch (self) {
            .EXR => "exr",
            .PNG => "png",
            .RGBE => "hdr",
        };
    }
};
