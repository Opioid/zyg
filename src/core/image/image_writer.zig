const EXR = @import("encoding/exr/exr_writer.zig").Writer;
pub const PNG = @import("encoding/png/png_writer.zig").Writer;
const RGBE = @import("encoding/rgbe/rgbe_writer.zig").Writer;

const img = @import("image.zig");
const Float4 = img.Float4;
const AovClass = @import("../rendering/sensor/aov/aov_value.zig").Value.Class;

const base = @import("base");
const Vec4i = base.math.Vec4i;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Writer = union(enum) {
    pub const Encoding = enum {
        Color,
        ColorAlpha,
        Normal,
        Depth,
        Id,
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
        crop: Vec4i,
        encoding: Encoding,
        threads: *Threads,
    ) !void {
        switch (self.*) {
            .EXR => |w| try w.write(alloc, writer, .{ .Float4 = image }, crop, encoding, threads),
            .PNG => |*w| try w.write(alloc, writer, image, crop, encoding, threads),
            .RGBE => try RGBE.write(alloc, writer, image, crop),
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
