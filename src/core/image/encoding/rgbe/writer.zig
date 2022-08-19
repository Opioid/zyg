const img = @import("../../image.zig");
const Float4 = img.Float4;

const base = @import("base");
const math = base.math;
const Pack4f = math.Pack4f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Writer = struct {
    pub fn write(alloc: Allocator, writer: anytype, image: Float4) !void {
        try writeHeader(writer, image);

        try writePixelsRle(alloc, writer, image);
    }

    fn writeHeader(writer: anytype, image: Float4) !void {
        const d = image.description.dimensions;

        try writer.writeAll("#?RGBE\n");
        try writer.writeAll("FORMAT=32-bit_rle_rgbe\n\n");

        var buf: [32]u8 = undefined;
        const printed = try std.fmt.bufPrint(&buf, "-Y {d} +X {d}\n", .{ d[1], d[0] });
        try writer.writeAll(printed);
    }

    fn writePixelsRle(alloc: Allocator, writer: anytype, image: Float4) !void {
        const d = image.description.dimensions;

        const scanline_width = @intCast(u32, d[0]);
        var num_scanlines = d[1];

        if (scanline_width < 8 or scanline_width > 0x7fff) {
            // run length encoding is not allowed so write flat
            return writePixels(writer, image);
        }

        var buffer = try alloc.alloc(u8, @intCast(usize, scanline_width * 4));
        defer alloc.free(buffer);

        var current_pixel: u32 = 0;
        while (num_scanlines > 0) : (num_scanlines -= 1) {
            const info: [4]u8 = .{
                2,
                2,
                @intCast(u8, scanline_width >> 8),
                @intCast(u8, scanline_width & 0xFF),
            };

            try writer.writeAll(&info);

            var i: u32 = 0;
            while (i < scanline_width) : (i += 1) {
                const rgbe = floatToRgbe(@maximum(@as(Vec4f, image.pixels[current_pixel].v), @splat(4, @as(f32, 0.0))));

                buffer[i] = rgbe[0];
                buffer[i + scanline_width] = rgbe[1];
                buffer[i + scanline_width * 2] = rgbe[2];
                buffer[i + scanline_width * 3] = rgbe[3];

                current_pixel += 1;
            }

            // write out each of the four channels separately run length encoded
            // first red, then green, then blue, then exponent
            i = 0;
            while (i < 4) : (i += 1) {
                const begin = @intCast(usize, i * scanline_width);
                const end = begin + scanline_width;
                try writeBytesRle(writer, buffer[begin..end]);
            }
        }
    }

    fn writePixels(writer: anytype, image: Float4) !void {
        for (image.pixels) |p| {
            const rgbe = floatToRgbe(@maximum(@as(Vec4f, p.v), @splat(4, @as(f32, 0.0))));

            try writer.writeAll(&rgbe);
        }
    }

    fn writeBytesRle(writer: anytype, data: []u8) !void {
        const Min_run_length = comptime 4;

        var buffer: [2]u8 = undefined;
        var current: u32 = 0;

        while (current < data.len) {
            var begin_run = current;

            // find next run of length at least 4 if one exists
            var run_count: u32 = 0;
            var old_run_count: u32 = 0;

            while (run_count < Min_run_length and begin_run < data.len) {
                begin_run += run_count;
                old_run_count = run_count;
                run_count = 1;

                while (begin_run + run_count < data.len and run_count < 127 and
                    data[begin_run] == data[begin_run + run_count])
                {
                    run_count += 1;
                }
            }

            // if data before next big run is a short run then write it as such
            if (old_run_count > 1 and old_run_count == begin_run - current) {
                buffer[0] = @intCast(u8, 128 + old_run_count); // write short run
                buffer[1] = data[current];

                try writer.writeAll(&buffer);

                current = begin_run;
            }

            // write out bytes until we reach the start of the next run
            while (current < begin_run) {
                var nonrun_count = begin_run - current;

                if (nonrun_count > 128) {
                    nonrun_count = 128;
                }

                buffer[0] = @intCast(u8, nonrun_count);

                try writer.writeByte(buffer[0]);
                try writer.writeAll(data[current .. current + nonrun_count]);

                current += nonrun_count;
            }

            // write out next run if one was found
            if (run_count >= Min_run_length) {
                buffer[0] = @intCast(u8, 128 + run_count);
                buffer[1] = data[begin_run];

                try writer.writeAll(&buffer);

                current += run_count;
            }
        }
    }

    fn floatToRgbe(c: Vec4f) [4]u8 {
        var v = c[0];

        if (c[1] > v) {
            v = c[1];
        }

        if (c[2] > v) {
            v = c[2];
        }

        if (v < 1.0e-32) {
            return .{ 0, 0, 0, 0 };
        }

        const f = std.math.frexp(v);

        v = f.significand * 256.0 / v;

        return .{
            @floatToInt(u8, c[0] * v),
            @floatToInt(u8, c[1] * v),
            @floatToInt(u8, c[2] * v),
            @intCast(u8, f.exponent + 128),
        };
    }
};
