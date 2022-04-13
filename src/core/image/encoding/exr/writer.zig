const exr = @import("exr.zig");
const img = @import("../../image.zig");
const Float4 = img.Float4;
const AovClass = @import("../../../rendering/sensor/aov/value.zig").Value.Class;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Pack4f = math.Pack4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

const mz = @cImport({
    @cInclude("miniz/miniz.h");
});

pub const Writer = struct {
    half: bool,
    alpha: bool,

    const Self = @This();

    pub fn write(
        self: Self,
        alloc: Allocator,
        writer_: anytype,
        image: Float4,
        aov: ?AovClass,
        threads: *Threads,
    ) !void {
        var stream = std.io.countingWriter(writer_);
        var writer = stream.writer();

        try writer.writeAll(&exr.Signature);

        const version = [4]u8{ 2, 0, 0, 0 };
        try writer.writeAll(&version);

        var format: exr.Channel.Format = if (self.half) .Half else .Float;

        var num_channels: u32 = 3;

        if (aov) |a| {
            switch (a) {
                .Depth => {
                    num_channels = 1;
                    format = .Float;
                },
                .MaterialId => {
                    num_channels = 1;
                    format = .Uint;
                },
                else => {},
            }
        } else if (self.alpha) {
            num_channels = 4;
        }

        {
            try writeString(writer, "channels");
            try writeString(writer, "chlist");

            const size = num_channels * (2 + 4 + 4 + 4 + 4) + 1;
            try writer.writeAll(std.mem.asBytes(&size));

            if (num_channels == 4) {
                try writeChannel(writer, .{ .name = "A", .format = format });
            }

            if (num_channels >= 3) {
                try writeChannel(writer, .{ .name = "B", .format = format });
                try writeChannel(writer, .{ .name = "G", .format = format });
            }

            if (num_channels == 1) {
                try writeChannel(writer, .{ .name = "Y", .format = format });
            } else {
                try writeChannel(writer, .{ .name = "R", .format = format });
            }

            try writer.writeByte(0x00);
        }

        const compression = exr.Compression.ZIP;

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
            try noCompression(writer, image, num_channels, format);
        } else if (.ZIP == compression) {
            try zipCompression(alloc, writer, image, num_channels, format, compression, threads);
        }
    }

    fn noCompression(
        writer: anytype,
        image: Float4,
        num_channels: u32,
        format: exr.Channel.Format,
    ) !void {
        const d = image.description.dimensions;

        const scanline_offset = writer.context.bytes_written + @intCast(u64, d.v[1]) * 8;

        const scalar_size = format.byteSize();
        const bytes_per_row = @intCast(u32, d.v[0]) * num_channels * scalar_size;
        const row_size = 4 + 4 + bytes_per_row;

        const height = @intCast(u32, d.v[1]);

        var y: u32 = 0;
        while (y < height) : (y += 1) {
            try writeScalar(u64, writer, scanline_offset + y * row_size);
        }

        y = 0;
        while (y < height) : (y += 1) {
            try writeScalar(u32, writer, y);
            try writeScalar(u32, writer, bytes_per_row);

            if (num_channels == 4) {
                try writeScanline(writer, image, y, 3, format);
            }

            if (num_channels >= 3) {
                try writeScanline(writer, image, y, 2, format);
                try writeScanline(writer, image, y, 1, format);
            }

            try writeScanline(writer, image, y, 0, format);
        }
    }

    fn writeScanline(writer: anytype, image: Float4, y: i32, channel: u32, format: exr.Channel.Format) !void {
        const width = image.description.dimensions.v[0];

        if (.Uint == format) {
            var x: i32 = 0;
            while (x < width) : (x += 1) {
                const s = image.get2D(x, y).v[channel];
                const ui = @floatToInt(u32, s);
                try writer.writeAll(std.mem.asBytes(&ui));
            }
        } else if (.Half == format) {
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

    fn zipCompression(
        alloc: Allocator,
        writer: anytype,
        image: Float4,
        num_channels: u32,
        format: exr.Channel.Format,
        compression: exr.Compression,
        threads: *Threads,
    ) !void {
        const d = image.description.dimensions;

        const rows_per_block = compression.numScanlinesPerBlock();
        const row_blocks = compression.numScanlineBlocks(@intCast(u32, d.v[1]));

        const scalar_size = format.byteSize();

        const bytes_per_row = @intCast(u32, d.v[0]) * num_channels * scalar_size;
        const bytes_per_block = math.roundUp(u32, bytes_per_row * rows_per_block, 64);

        var context = Context{
            .rows_per_block = rows_per_block,
            .row_blocks = row_blocks,
            .num_channels = num_channels,
            .bytes_per_row = bytes_per_row,
            .bytes_per_block = bytes_per_block,
            .format = format,
            .image_buffer = try alloc.alloc(u8, @intCast(u32, d.v[1]) * bytes_per_row),
            .tmp_buffer = try alloc.alloc(u8, bytes_per_block * threads.numThreads()),
            .block_buffer = try alloc.alloc(u8, bytes_per_block * threads.numThreads()),
            .cb = try alloc.alloc(CompressedBlock, row_blocks),
            .image = &image,
        };

        defer {
            alloc.free(context.cb);
            alloc.free(context.block_buffer);
            alloc.free(context.tmp_buffer);
            alloc.free(context.image_buffer);
        }

        _ = threads.runRange(&context, Context.compress, 0, row_blocks, 0);

        var scanline_offset = writer.context.bytes_written + row_blocks * 8;

        var y: u32 = 0;
        while (y < row_blocks) : (y += 1) {
            try writeScalar(u64, writer, scanline_offset);

            scanline_offset += 4 + 4 + context.cb[y].size;
        }

        y = 0;
        while (y < row_blocks) : (y += 1) {
            const b = context.cb[y];

            const row = y * rows_per_block;
            try writeScalar(u32, writer, row);
            try writeScalar(u32, writer, b.size);
            try writer.writeAll(b.buffer[0..b.size]);
        }
    }

    const CompressedBlock = struct {
        size: u32,
        buffer: [*]u8,
    };

    const Context = struct {
        rows_per_block: u32,
        row_blocks: u32,
        num_channels: u32,
        bytes_per_row: u32,
        bytes_per_block: u32,

        format: exr.Channel.Format,

        image_buffer: []u8,
        tmp_buffer: []u8,
        block_buffer: []u8,

        cb: []CompressedBlock,

        image: *const Float4,

        fn compress(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            const self = @intToPtr(*Context, context);

            var zip: mz.mz_stream = undefined;
            zip.zalloc = null;
            zip.zfree = null;

            if (mz.MZ_OK != mz.mz_deflateInit(&zip, mz.MZ_DEFAULT_COMPRESSION)) {
                return;
            }

            const width = @intCast(u32, self.image.description.dimensions.v[0]);
            const height = @intCast(u32, self.image.description.dimensions.v[1]);
            const bpb = self.bytes_per_block;
            const offset = id * bpb;

            var tmp_buffer = self.tmp_buffer[offset .. offset + bpb];
            var block_buffer = self.block_buffer[offset .. offset + bpb];

            var y = begin;
            while (y < end) : (y += 1) {
                const num_rows_here = @minimum(height - (y * self.rows_per_block), self.rows_per_block);

                const pixel = y * self.rows_per_block * width;

                if (.Uint == self.format) {
                    blockUint(block_buffer, self.image.*, self.num_channels, num_rows_here, pixel);
                } else if (.Half == self.format) {
                    blockHalf(block_buffer, self.image.*, self.num_channels, num_rows_here, pixel);
                } else {
                    blockFloat(block_buffer, self.image.*, self.num_channels, num_rows_here, pixel);
                }

                const bytes_here = num_rows_here * self.bytes_per_row;
                reorder(tmp_buffer[0..bytes_here], block_buffer[0..bytes_here]);

                const image_buffer = self.image_buffer.ptr + y * bpb;

                zip.next_in = tmp_buffer.ptr;
                zip.avail_in = bytes_here;

                zip.next_out = image_buffer;
                zip.avail_out = bytes_here;

                _ = mz.mz_deflate(&zip, mz.MZ_FINISH);
                _ = mz.mz_deflateReset(&zip);

                const compressed_size = bytes_here - zip.avail_out;

                var cb = &self.cb[y];

                if (compressed_size >= bytes_here) {
                    cb.size = bytes_here;
                    cb.buffer = image_buffer;

                    std.mem.copy(u8, image_buffer[0..bytes_here], block_buffer[0..bytes_here]);
                } else {
                    cb.size = compressed_size;
                    cb.buffer = image_buffer;
                }
            }

            _ = mz.mz_deflateEnd(&zip);
        }

        fn blockHalf(destination: []u8, image: Float4, num_channels: u32, num_rows: u32, pixel: u32) void {
            const width = @intCast(u32, image.description.dimensions.v[0]);

            var halfs = std.mem.bytesAsSlice(f16, destination);

            var current = pixel;
            var row: u32 = 0;
            while (row < num_rows) : (row += 1) {
                const o = row * width * num_channels;
                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    const c = image.pixels[current];

                    if (4 == num_channels) {
                        halfs[o + width * 0 + x] = @floatCast(f16, c.v[3]);
                        halfs[o + width * 1 + x] = @floatCast(f16, c.v[2]);
                        halfs[o + width * 2 + x] = @floatCast(f16, c.v[1]);
                        halfs[o + width * 3 + x] = @floatCast(f16, c.v[0]);
                    } else if (3 == num_channels) {
                        halfs[o + width * 0 + x] = @floatCast(f16, c.v[2]);
                        halfs[o + width * 1 + x] = @floatCast(f16, c.v[1]);
                        halfs[o + width * 2 + x] = @floatCast(f16, c.v[0]);
                    } else {
                        halfs[o + width * 0 + x] = @floatCast(f16, c.v[0]);
                    }

                    current += 1;
                }
            }
        }

        fn blockUint(destination: []u8, image: Float4, num_channels: u32, num_rows: u32, pixel: u32) void {
            const width = @intCast(u32, image.description.dimensions.v[0]);

            var uints = std.mem.bytesAsSlice(u32, destination);

            var current = pixel;
            var row: u32 = 0;
            while (row < num_rows) : (row += 1) {
                const o = row * width * num_channels;
                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    const c = image.pixels[current];

                    uints[o + width * 0 + x] = @floatToInt(u32, c.v[0]);

                    current += 1;
                }
            }
        }

        fn blockFloat(destination: []u8, image: Float4, num_channels: u32, num_rows: u32, pixel: u32) void {
            const width = @intCast(u32, image.description.dimensions.v[0]);

            var floats = std.mem.bytesAsSlice(f32, destination);

            var current = pixel;
            var row: u32 = 0;
            while (row < num_rows) : (row += 1) {
                const o = row * width * num_channels;
                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    const c = image.pixels[current];

                    if (4 == num_channels) {
                        floats[o + width * 0 + x] = c.v[3];
                        floats[o + width * 1 + x] = c.v[2];
                        floats[o + width * 2 + x] = c.v[1];
                        floats[o + width * 3 + x] = c.v[0];
                    } else if (3 == num_channels) {
                        floats[o + width * 0 + x] = c.v[2];
                        floats[o + width * 1 + x] = c.v[1];
                        floats[o + width * 2 + x] = c.v[0];
                    } else {
                        floats[o + width * 0 + x] = c.v[0];
                    }

                    current += 1;
                }
            }
        }

        fn reorder(destination: []u8, source: []const u8) void {
            const len = destination.len;

            // Reorder the pixel data.
            {
                var t1: usize = 0;
                var t2 = (len + 1) / 2;

                var current: usize = 0;

                while (true) {
                    if (current < len) {
                        destination[t1] = source[current];

                        t1 += 1;
                        current += 1;
                    } else {
                        break;
                    }

                    if (current < len) {
                        destination[t2] = source[current];

                        t2 += 1;
                        current += 1;
                    } else {
                        break;
                    }
                }
            }

            // Predictor
            {
                var p = @intCast(u32, destination[0]);

                var t: usize = 1;
                while (t < len) : (t += 1) {
                    const b = destination[t];
                    const d = @intCast(u32, b) -% p +% (128 + 256);

                    p = b;
                    destination[t] = @truncate(u8, d);
                }
            }
        }
    };

    fn writeScalar(comptime T: type, writer: anytype, i: T) !void {
        try writer.writeAll(std.mem.asBytes(&i));
    }

    fn writeString(writer: anytype, text: []const u8) !void {
        try writer.writeAll(text);
        try writer.writeByte(0x00);
    }

    fn writeChannel(writer: anytype, channel: exr.Channel) !void {
        try writeString(writer, channel.name);

        try writer.writeAll(std.mem.asBytes(&channel.format));

        try writeScalar(u32, writer, 0);

        const sampling: u32 = 1;
        try writeScalar(u32, writer, sampling);
        try writeScalar(u32, writer, sampling);
    }
};
