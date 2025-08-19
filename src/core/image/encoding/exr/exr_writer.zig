const exr = @import("exr.zig");
const img = @import("../../image.zig");
const Image = img.Image;
const Float4 = img.Float4;
const Encoding = @import("../../image_writer.zig").Writer.Encoding;
const AovClass = @import("../../../rendering/sensor/aov/aov_value.zig").Value.Class;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;
const Pack4f = math.Pack4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

const mz = @cImport({
    @cInclude("miniz/miniz.h");
});

pub const Writer = struct {
    half: bool,

    const Self = @This();

    pub fn write(
        self: Self,
        alloc: Allocator,
        writer_: *std.Io.Writer,
        image: Image,
        crop: Vec4i,
        encoding: Encoding,
        threads: *Threads,
    ) !void {
        var header: std.io.Writer.Allocating = .init(alloc);
        var writer = &header.writer;

        try writer.writeAll(&exr.Signature);

        const version = [4]u8{ 2, 0, 0, 0 };
        try writer.writeAll(&version);

        var format: exr.Channel.Format = if (self.half) .Half else .Float;

        var num_channels: u32 = 3;

        switch (encoding) {
            .ColorAlpha => num_channels = 4,
            .Depth => {
                num_channels = 1;
                format = .Float;
            },
            .Id => {
                num_channels = 1;
                format = .Uint;
            },
            else => {},
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
            try writer.writeByte(@intFromEnum(compression));
        }

        {
            try writeString(writer, "dataWindow");
            try writeString(writer, "box2i");
            try writeScalar(u32, writer, 16);

            try writeScalar(i32, writer, crop[0]);
            try writeScalar(i32, writer, crop[1]);

            try writeScalar(i32, writer, crop[2] - 1);
            try writeScalar(i32, writer, crop[3] - 1);
        }

        {
            const d = image.dimensions();

            try writeString(writer, "displayWindow");
            try writeString(writer, "box2i");
            try writeScalar(u32, writer, 16);

            try writeScalar(u32, writer, 0);
            try writeScalar(u32, writer, 0);

            try writeScalar(i32, writer, d[0] - 1);
            try writeScalar(i32, writer, d[1] - 1);
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

        const header_buf = header.written();
        const header_size = header_buf.len;
        try writer_.writeAll(header_buf);
        header.deinit();

        if (.No == compression) {
            switch (image) {
                inline .Float3, .Float4 => |im| try noCompression(@TypeOf(im), writer_, header_size, im, crop, num_channels, format),
                else => {},
            }
        } else if (.ZIP == compression) {
            try zipCompression(alloc, writer_, header_size, image, crop, num_channels, format, compression, threads);
        }
    }

    fn noCompression(
        comptime T: type,
        writer: *std.Io.Writer,
        bytes_written: usize,
        image: T,
        crop: Vec4i,
        num_channels: u32,
        format: exr.Channel.Format,
    ) !void {
        const xy = Vec2i{ crop[0], crop[1] };
        const zw = Vec2i{ crop[2], crop[3] };
        const dim = zw - xy;

        const scanline_offset = bytes_written + @as(u64, @intCast(dim[1])) * 8;

        const scalar_size = format.byteSize();
        const bytes_per_row = @as(u32, @intCast(dim[0])) * num_channels * scalar_size;
        const row_size = 4 + 4 + bytes_per_row;

        var y: i32 = 0;
        while (y < dim[1]) : (y += 1) {
            try writeScalar(u64, writer, scanline_offset + @as(u64, @intCast(y)) * row_size);
        }

        y = crop[1];
        while (y < crop[3]) : (y += 1) {
            try writeScalar(i32, writer, y);
            try writeScalar(u32, writer, bytes_per_row);

            if (num_channels == 4) {
                try writeScanline(T, writer, image, crop, y, 3, format);
            }

            if (num_channels >= 3) {
                try writeScanline(T, writer, image, crop, y, 2, format);
                try writeScanline(T, writer, image, crop, y, 1, format);
            }

            try writeScanline(T, writer, image, crop, y, 0, format);
        }
    }

    fn writeScanline(
        comptime T: type,
        writer: *std.Io.Writer,
        image: T,
        crop: Vec4i,
        y: i32,
        channel: u32,
        format: exr.Channel.Format,
    ) !void {
        const x_end = crop[2];

        if (.Uint == format) {
            var x: i32 = crop[0];
            while (x < x_end) : (x += 1) {
                const s = image.get2D(x, y).v[channel];
                const ui = @as(u32, @intFromFloat(s));
                try writer.writeAll(std.mem.asBytes(&ui));
            }
        } else if (.Half == format) {
            var x: i32 = crop[0];
            while (x < x_end) : (x += 1) {
                const s = image.get2D(x, y).v[channel];
                const h = @as(f16, @floatCast(s));
                try writer.writeAll(std.mem.asBytes(&h));
            }
        } else {
            var x: i32 = crop[0];
            while (x < x_end) : (x += 1) {
                const s = image.get2D(x, y).v[channel];
                try writer.writeAll(std.mem.asBytes(&s));
            }
        }
    }

    fn zipCompression(
        alloc: Allocator,
        writer: *std.Io.Writer,
        bytes_written: usize,
        image: Image,
        crop: Vec4i,
        num_channels: u32,
        format: exr.Channel.Format,
        compression: exr.Compression,
        threads: *Threads,
    ) !void {
        const xy = Vec2i{ crop[0], crop[1] };
        const zw = Vec2i{ crop[2], crop[3] };
        const dim = zw - xy;

        const rows_per_block = compression.numScanlinesPerBlock();
        const row_blocks = compression.numScanlineBlocks(@as(u32, @intCast(dim[1])));

        const scalar_size = format.byteSize();

        const bytes_per_row = @as(u32, @intCast(dim[0])) * num_channels * scalar_size;
        const bytes_per_block = math.roundUp(u32, bytes_per_row * rows_per_block, 64);

        var context = Context{
            .rows_per_block = rows_per_block,
            .row_blocks = row_blocks,
            .num_channels = num_channels,
            .bytes_per_row = bytes_per_row,
            .bytes_per_block = bytes_per_block,
            .format = format,
            .image_buffer = try alloc.alloc(u8, @as(u32, @intCast(dim[1])) * bytes_per_row),
            .tmp_buffer = try alloc.alloc(u8, bytes_per_block * threads.numThreads()),
            .block_buffer = try alloc.alloc(u8, bytes_per_block * threads.numThreads()),
            .cb = try alloc.alloc(CompressedBlock, row_blocks),
            .image = &image,
            .crop = crop,
        };

        defer {
            alloc.free(context.cb);
            alloc.free(context.block_buffer);
            alloc.free(context.tmp_buffer);
            alloc.free(context.image_buffer);
        }

        _ = threads.runRange(&context, Context.compress, 0, row_blocks, 0);

        var scanline_offset = bytes_written + row_blocks * 8;

        var y: u32 = 0;
        while (y < row_blocks) : (y += 1) {
            try writeScalar(u64, writer, scanline_offset);

            scanline_offset += 4 + 4 + context.cb[y].size;
        }

        const y_offset: u32 = @intCast(crop[1]);

        y = 0;
        while (y < row_blocks) : (y += 1) {
            const b = context.cb[y];

            const row = y_offset + y * rows_per_block;
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

        image: *const Image,
        crop: Vec4i,

        fn compress(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            const self: *Context = @ptrCast(@alignCast(context));

            var zip: mz.mz_stream = undefined;
            zip.zalloc = null;
            zip.zfree = null;

            if (mz.MZ_OK != mz.mz_deflateInit(&zip, mz.MZ_UBER_COMPRESSION)) {
                return;
            }

            const num_channels = self.num_channels;
            const crop = self.crop;

            const xy = Vec2i{ crop[0], crop[1] };
            const zw = Vec2i{ crop[2], crop[3] };
            const dim = zw - xy;

            const width: u32 = @intCast(dim[0]);
            const height: u32 = @intCast(dim[1]);
            const bpb = self.bytes_per_block;
            const offset = id * bpb;

            const x_start: u32 = @intCast(crop[0]);
            const y_start: u32 = @intCast(crop[1]);

            var tmp_buffer = self.tmp_buffer[offset .. offset + bpb];
            var block_buffer = self.block_buffer[offset .. offset + bpb];

            var y = begin;
            while (y < end) : (y += 1) {
                const num_rows_here = @min(height - (y * self.rows_per_block), self.rows_per_block);

                const row = y_start + y * self.rows_per_block;

                switch (self.image.*) {
                    inline .Float3, .Float4 => |im| {
                        if (.Uint == self.format) {
                            blockUint(@TypeOf(im), block_buffer, im, num_channels, x_start, row, width, num_rows_here);
                        } else if (.Half == self.format) {
                            blockHalf(@TypeOf(im), block_buffer, im, num_channels, x_start, row, width, num_rows_here);
                        } else {
                            blockFloat(@TypeOf(im), block_buffer, im, num_channels, x_start, row, width, num_rows_here);
                        }
                    },
                    else => {},
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

                    @memcpy(image_buffer[0..bytes_here], block_buffer[0..bytes_here]);
                } else {
                    cb.size = compressed_size;
                    cb.buffer = image_buffer;
                }
            }

            _ = mz.mz_deflateEnd(&zip);
        }

        fn blockHalf(comptime T: type, destination: []u8, image: T, num_channels: u32, data_x: u32, data_y: u32, num_x: u32, num_y: u32) void {
            const data_width: u32 = @intCast(image.dimensions[0]);

            var halfs = std.mem.bytesAsSlice(f16, destination);

            var row: u32 = 0;
            while (row < num_y) : (row += 1) {
                const o = row * num_x * num_channels;

                var current = (data_y + row) * data_width + data_x;

                var x: u32 = 0;
                while (x < num_x) : (x += 1) {
                    const c = image.pixels[current];

                    if (4 == num_channels) {
                        if (Float4 == T) {
                            halfs[o + num_x * 0 + x] = @floatCast(c.v[3]);
                        }

                        halfs[o + num_x * 1 + x] = @floatCast(c.v[2]);
                        halfs[o + num_x * 2 + x] = @floatCast(c.v[1]);
                        halfs[o + num_x * 3 + x] = @floatCast(c.v[0]);
                    } else if (3 == num_channels) {
                        halfs[o + num_x * 0 + x] = @floatCast(c.v[2]);
                        halfs[o + num_x * 1 + x] = @floatCast(c.v[1]);
                        halfs[o + num_x * 2 + x] = @floatCast(c.v[0]);
                    } else {
                        halfs[o + num_x * 0 + x] = @floatCast(c.v[0]);
                    }

                    current += 1;
                }
            }
        }

        fn blockUint(comptime T: type, destination: []u8, image: T, num_channels: u32, data_x: u32, data_y: u32, num_x: u32, num_y: u32) void {
            const data_width = @as(u32, @intCast(image.dimensions[0]));

            var uints = std.mem.bytesAsSlice(u32, destination);

            var row: u32 = 0;
            while (row < num_y) : (row += 1) {
                const o = row * num_x * num_channels;

                var current = (data_y + row) * data_width + data_x;

                var x: u32 = 0;
                while (x < num_x) : (x += 1) {
                    const c = image.pixels[current];

                    uints[o + num_x * 0 + x] = @intFromFloat(c.v[0]);

                    current += 1;
                }
            }
        }

        fn blockFloat(comptime T: type, destination: []u8, image: T, num_channels: u32, data_x: u32, data_y: u32, num_x: u32, num_y: u32) void {
            const data_width: u32 = @intCast(image.dimensions[0]);

            var floats = std.mem.bytesAsSlice(f32, destination);

            var row: u32 = 0;
            while (row < num_y) : (row += 1) {
                const o = row * num_x * num_channels;

                var current = (data_y + row) * data_width + data_x;

                var x: u32 = 0;
                while (x < num_x) : (x += 1) {
                    const c = image.pixels[current];

                    if (4 == num_channels) {
                        if (Float4 == T) {
                            floats[o + num_x * 0 + x] = c.v[3];
                        }

                        floats[o + num_x * 1 + x] = c.v[2];
                        floats[o + num_x * 2 + x] = c.v[1];
                        floats[o + num_x * 3 + x] = c.v[0];
                    } else if (3 == num_channels) {
                        floats[o + num_x * 0 + x] = c.v[2];
                        floats[o + num_x * 1 + x] = c.v[1];
                        floats[o + num_x * 2 + x] = c.v[0];
                    } else {
                        floats[o + num_x * 0 + x] = c.v[0];
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
                var p: u32 = @intCast(destination[0]);

                var t: usize = 1;
                while (t < len) : (t += 1) {
                    const b = destination[t];
                    const d = @as(u32, @intCast(b)) -% p +% (128 + 256);

                    p = b;
                    destination[t] = @truncate(d);
                }
            }
        }
    };

    fn writeScalar(comptime T: type, writer: *std.Io.Writer, i: T) !void {
        try writer.writeAll(std.mem.asBytes(&i));
    }

    fn writeString(writer: *std.Io.Writer, text: []const u8) !void {
        try writer.writeAll(text);
        try writer.writeByte(0x00);
    }

    fn writeChannel(writer: *std.Io.Writer, channel: exr.Channel) !void {
        try writeString(writer, channel.name);

        try writer.writeAll(std.mem.asBytes(&channel.format));

        try writeScalar(u32, writer, 0);

        const sampling: u32 = 1;
        try writeScalar(u32, writer, sampling);
        try writeScalar(u32, writer, sampling);
    }
};
