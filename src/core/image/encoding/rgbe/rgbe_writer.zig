const img = @import("../../image.zig");
const Float4 = img.Float4;

const base = @import("base");
const math = base.math;
const Pack4f = math.Pack4f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Writer = struct {
    pub fn write(alloc: Allocator, writer: anytype, image: Float4, crop: Vec4i) !void {
        try writeHeader(writer, image);

        try writePixelsRle(alloc, writer, image, crop);
    }

    fn writeHeader(writer: anytype, image: Float4) !void {
        const d = image.description.dimensions;

        try writer.writeAll("#?RGBE\n");
        try writer.writeAll("FORMAT=32-bit_rle_rgbe\n\n");

        var buf: [32]u8 = undefined;
        const printed = try std.fmt.bufPrint(&buf, "-Y {d} +X {d}\n", .{ d[1], d[0] });
        try writer.writeAll(printed);
    }

    fn writePixelsRle(alloc: Allocator, writer: anytype, image: Float4, crop: Vec4i) !void {
        const d = image.description.dimensions;

        const width = @as(u32, @intCast(d[0]));
        const height = @as(u32, @intCast(d[1]));

        if (width < 8 or width > 0x7fff) {
            // run length encoding is not allowed so write flat
            return writePixels(writer, image, crop);
        }

        var buffer = try alloc.alloc(u8, @as(usize, @intCast(width * 4)));
        defer alloc.free(buffer);

        var current_pixel: u32 = 0;

        var y: u32 = 0;
        while (y < height) : (y += 1) {
            const info: [4]u8 = .{
                2,
                2,
                @as(u8, @intCast(width >> 8)),
                @as(u8, @intCast(width & 0xFF)),
            };

            try writer.writeAll(&info);

            if (y < crop[1] or y >= crop[3]) {
                @memset(buffer, 0);
                current_pixel += width;
            } else {
                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    if (x < crop[0] or x >= crop[2]) {
                        buffer[x * 4 + 0] = 0;
                        buffer[x * 4 + 1] = 0;
                        buffer[x * 4 + 2] = 0;
                        buffer[x * 4 + 3] = 0;
                    } else {
                        const rgbe = floatToRgbe(math.max4(@as(Vec4f, image.pixels[current_pixel].v), @splat(4, @as(f32, 0.0))));

                        buffer[x + width * 0] = rgbe[0];
                        buffer[x + width * 1] = rgbe[1];
                        buffer[x + width * 2] = rgbe[2];
                        buffer[x + width * 3] = rgbe[3];
                    }

                    current_pixel += 1;
                }
            }

            // write out each of the four channels separately run length encoded
            // first red, then green, then blue, then exponent
            var i: u32 = 0;
            while (i < 4) : (i += 1) {
                const begin = i * width;
                const end = begin + width;
                try writeBytesRle(writer, buffer[begin..end]);
            }
        }
    }

    fn writePixels(writer: anytype, image: Float4, crop: Vec4i) !void {
        const d = image.description.dimensions;

        var i: u32 = 0;

        var y: i32 = 0;
        while (y < d[1]) {
            var x: i32 = 0;
            while (x < d[0]) {
                if (y < crop[1] or y >= crop[3] or x < crop[0] or x >= crop[2]) {
                    const zero = [_]u8{0} ** 4;
                    try writer.writeAll(&zero);
                } else {
                    const p = image.pixels[i];

                    const rgbe = floatToRgbe(math.max4(@as(Vec4f, p.v), @splat(4, @as(f32, 0.0))));

                    try writer.writeAll(&rgbe);
                }

                i += 1;
            }
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
                buffer[0] = @as(u8, @intCast(128 + old_run_count)); // write short run
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

                buffer[0] = @as(u8, @intCast(nonrun_count));

                try writer.writeByte(buffer[0]);
                try writer.writeAll(data[current .. current + nonrun_count]);

                current += nonrun_count;
            }

            // write out next run if one was found
            if (run_count >= Min_run_length) {
                buffer[0] = @as(u8, @intCast(128 + run_count));
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
            @intFromFloat(c[0] * v),
            @intFromFloat(c[1] * v),
            @intFromFloat(c[2] * v),
            @intCast(f.exponent + 128),
        };
    }
};
