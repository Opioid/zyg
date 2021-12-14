const exr = @import("exr.zig");
const img = @import("../../image.zig");
const Float4 = img.Float4;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Pack4f = math.Pack4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Writer = struct {
    half: bool = true,
    alpha: bool,

    //  const Stream = std.io.CountingWriter(std.fs.File.Writer).Writer;

    const Self = @This();

    pub fn write(
        self: Self,
        alloc: Allocator,
        writer_: anytype,
        image: Float4,
        threads: *Threads,
    ) !void {
        _ = alloc;
        _ = threads;

        var stream = std.io.countingWriter(writer_);
        var writer = stream.writer();

        try writer.writeAll(&exr.Signature);

        const version = [4]u8{ 2, 0, 0, 0 };
        try writer.writeAll(&version);

        {
            try writeString(writer, "channels");
            try writeString(writer, "chlist");

            const num_channels: u32 = if (self.alpha) 4 else 3;
            const size = num_channels * (2 + 4 + 4 + 4 + 4) + 1;
            try writer.writeAll(std.mem.asBytes(&size));

            const typef: exr.Channel.Type = if (self.half) .Half else .Float;

            if (self.alpha) {
                try writeChannel(writer, .{ .name = "A", .typef = typef });
            }

            try writeChannel(writer, .{ .name = "B", .typef = typef });
            try writeChannel(writer, .{ .name = "G", .typef = typef });
            try writeChannel(writer, .{ .name = "R", .typef = typef });
            try writer.writeByte(0x00);
        }

        const compression = exr.Compression.No;

        {
            try writeString(writer, "compression");
            try writeString(writer, "compression");
            try writeScalar(u32, writer, 1);
            try writer.writeByte(@enumToInt(compression));
        }

        const d = image.description.dimensions;
        const dw = Vec2i{ d.v[0] - 1, d.v[1] - 1 };

        {
            try writeString(writer, "dataWindow");
            try writeString(writer, "box2i");
            try writeScalar(u32, writer, 16);

            try writeScalar(u32, writer, 0);
            try writeScalar(u32, writer, 0);

            try writeScalar(i32, writer, dw[0]);
            try writeScalar(i32, writer, dw[1]);
        }

        {
            try writeString(writer, "displayWindow");
            try writeString(writer, "box2i");
            try writeScalar(u32, writer, 16);

            try writeScalar(u32, writer, 0);
            try writeScalar(u32, writer, 0);

            try writeScalar(i32, writer, dw[0]);
            try writeScalar(i32, writer, dw[1]);
        }

        {
            try writeString(writer, "lineOrder");
            try writeString(writer, "lineOrder");
            try writeScalar(u32, writer, 1);
            try writer.writeByte(0x00);
        }

        {
            try writeString(writer, "pixelAspectRatio");
            try writeString(writer, "float");
            try writeScalar(u32, writer, 4);
            try writeScalar(f32, writer, 1.0);
        }

        {
            try writeString(writer, "screenWindowCenter");
            try writeString(writer, "v2f");
            try writeScalar(u32, writer, 8);
            try writeScalar(f32, writer, 0.0);
            try writeScalar(f32, writer, 0.0);
        }

        {
            try writeString(writer, "screenWindowWidth");
            try writeString(writer, "float");
            try writeScalar(u32, writer, 4);
            try writeScalar(f32, writer, 1.0);
        }

        try writer.writeByte(0x00);

        if (.No == compression) {
            try self.noCompression(writer, image);
        }
    }

    fn noCompression(self: Writer, writer: anytype, image: Float4) !void {
        const d = image.description.dimensions;

        const scanline_offset: i64 = @intCast(i64, writer.context.bytes_written) + @intCast(i64, d.v[1]) * 8;

        const num_channels: i32 = if (self.alpha) 4 else 3;
        const scalar_size: i32 = if (self.half) 2 else 4;
        const bytes_per_row = d.v[0] * num_channels * scalar_size;
        const row_size = 4 + 4 + bytes_per_row;

        var y: i32 = 0;
        while (y < d.v[1]) : (y += 1) {
            try writeScalar(i64, writer, scanline_offset + y * row_size);
        }

        y = 0;
        while (y < d.v[1]) : (y += 1) {
            try writeScalar(i32, writer, y);
            try writeScalar(i32, writer, bytes_per_row);

            if (self.alpha) {
                try writeScanline(writer, image, y, 3, self.half);
            }

            try writeScanline(writer, image, y, 2, self.half);
            try writeScanline(writer, image, y, 1, self.half);
            try writeScanline(writer, image, y, 0, self.half);
        }
    }

    fn writeScanline(writer: anytype, image: Float4, y: i32, channel: u32, half: bool) !void {
        const width = image.description.dimensions.v[0];

        if (half) {
            var x: i32 = 0;
            while (x < width) : (x += 1) {
                const s = image.get2D(x, y).v[channel];
                const h = @floatCast(f16, s);
                try writer.writeAll(std.mem.asBytes(&h));
            }
        } else {
            var x: i32 = 0;
            while (x < width) : (x += 1) {
                const s = image.get2D(x, y).v[channel];
                try writer.writeAll(std.mem.asBytes(&s));
            }
        }
    }

    fn writeScalar(comptime T: type, writer: anytype, i: T) !void {
        try writer.writeAll(std.mem.asBytes(&i));
    }

    fn writeString(writer: anytype, text: []const u8) !void {
        try writer.writeAll(text);
        try writer.writeByte(0x00);
    }

    fn writeChannel(writer: anytype, channel: exr.Channel) !void {
        try writeString(writer, channel.name);

        try writer.writeAll(std.mem.asBytes(&channel.typef));

        try writeScalar(u32, writer, 0);

        const sampling: u32 = 1;
        try writeScalar(u32, writer, sampling);
        try writeScalar(u32, writer, sampling);
    }
};
