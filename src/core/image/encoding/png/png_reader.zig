const img = @import("../../image.zig");
const Image = img.Image;
const Swizzle = img.Swizzle;
const ReadStream = @import("../../../file/read_stream.zig").ReadStream;

const base = @import("base");
const math = base.math;
const Vec2b = math.Vec2b;
const Vec2i = math.Vec2i;
const Pack3b = math.Pack3b;
const Threads = base.thread.Pool;
const ThreadContext = Threads.Context;

const std = @import("std");
const Allocator = std.mem.Allocator;

const mz = @cImport({
    @cInclude("miniz/miniz.h");
});

const Signature = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };

pub const Reader = struct {
    const Error = error{
        BadPNGSignature,
        PNGBitDepthNotSupported,
        InterlacedPNGNotSupported,
        IndexedPNGNotSupperted,
        InitMZStreamFailed,
        InflateMZStreamFailed,
        UnexpectedError,
    };

    const Chunk = struct {
        length: u32 = 0,

        data: []u8 = &.{},

        pub fn allocate(self: *Chunk, alloc: Allocator) !void {
            if (self.data.len < self.length) {
                self.data = try alloc.realloc(self.data, self.length);
            }
        }

        pub fn deinit(self: *Chunk, alloc: Allocator) void {
            alloc.free(self.data);
        }
    };

    const Filter = enum(u8) { None, Sub, Up, Average, Paeth };

    const ColorType = enum(u8) {
        Grayscale = 0,
        Truecolor = 2,
        Palleted = 3,
        Grayscale_alpha = 4,
        Truecolor_alpha = 6,
    };

    const Info = struct {
        // header
        width: i32 = 0,
        height: i32 = 0,

        num_channels: u32 = 0,
        bytes_per_pixel: u32 = 0,

        // miniz
        stream: mz.mz_stream = undefined,

        data_chunks: std.ArrayListUnmanaged(Chunk) = .{},
        num_chunks: u32 = 0,

        buffer_data: []u8 = &.{},
        buffer: [*]u8 = undefined,

        filters: []Filter = &.{},

        image: Image = undefined,
        swizzle: Swizzle = undefined,
        invert: bool = undefined,
        byte_compatible: bool = undefined,

        pub fn init() Info {
            var info = Info{};

            info.stream.zalloc = null;
            info.stream.zfree = null;

            return info;
        }

        pub fn deinit(self: *Info, alloc: Allocator) void {
            alloc.free(self.buffer_data);

            for (self.data_chunks.items) |*c| {
                c.deinit(alloc);
            }

            self.data_chunks.deinit(alloc);

            if (self.stream.zfree) |_| {
                _ = mz.mz_inflateEnd(&self.stream);
            }
        }

        pub fn allocate(self: *Info, alloc: Allocator) !void {
            const height = @intCast(u32, self.height);
            const row_size = @intCast(u32, self.width) * self.num_channels;
            const buffer_size = row_size * height;
            const num_bytes = buffer_size + row_size;

            if (self.buffer_data.len < num_bytes) {
                self.buffer_data = try alloc.realloc(self.buffer_data, num_bytes);
            }

            self.buffer = self.buffer_data.ptr + row_size;

            if (self.filters.len < height) {
                self.filters = try alloc.realloc(self.filters, height);
            }

            self.num_chunks = 0;

            if (self.stream.zalloc) |_| {
                if (mz.MZ_OK != mz.mz_inflateReset(&self.stream)) {
                    return Error.InitMZStreamFailed;
                }
            } else {
                if (mz.MZ_OK != mz.mz_inflateInit(&self.stream)) {
                    return Error.InitMZStreamFailed;
                }
            }
        }

        pub fn allocateImage(self: *Info, alloc: Allocator, swizzle: Swizzle, invert: bool) !Image {
            var num_channels: u32 = switch (swizzle) {
                .X, .W => 1,
                .XY, .YX, .YZ => 2,
                .XYZ => 3,
                .XYZW => 3,
            };

            self.swizzle = swizzle;
            self.invert = invert;
            self.byte_compatible = num_channels == self.num_channels and .YX != swizzle;

            num_channels = @min(num_channels, self.num_channels);

            const dimensions = Vec2i{ self.width, self.height };

            if (1 == num_channels) {
                const image = try img.Byte1.init(alloc, img.Description.init2D(dimensions));
                self.image = .{ .Byte1 = image };
            }

            if (2 == num_channels) {
                const image = try img.Byte2.init(alloc, img.Description.init2D(dimensions));
                self.image = .{ .Byte2 = image };
            }

            if (3 == num_channels) {
                const image = try img.Byte3.init(alloc, img.Description.init2D(dimensions));
                self.image = .{ .Byte3 = image };
            }

            return self.image;
        }

        pub fn process(self: *const Info) !void {
            try self.parseData();
            self.resolveFilter();
            self.fillImage();
        }

        fn parseData(self: *const Info) !void {
            const buffer_size = 8192;
            var buffer: [buffer_size]u8 = undefined;

            const row_size = @intCast(u32, self.width) * self.num_channels;

            var filter_byte = true;
            var current_row: u32 = 0;
            var current_byte: u32 = 0;
            var current_byte_total: u32 = 0;

            var stream = self.stream;

            for (self.data_chunks.items[0..self.num_chunks]) |c| {
                stream.next_in = c.data.ptr;
                stream.avail_in = c.length;

                var cond = true;
                while (cond) {
                    stream.next_out = &buffer;
                    stream.avail_out = buffer_size;

                    const status = mz.mz_inflate(&stream, mz.MZ_NO_FLUSH);
                    if (status != mz.MZ_OK and status != mz.MZ_STREAM_END and status != mz.MZ_BUF_ERROR and status != mz.MZ_NEED_DICT) {
                        return Error.InflateMZStreamFailed;
                    }

                    const decompressed = buffer_size - stream.avail_out;

                    var i: u32 = 0;
                    while (i < decompressed) {
                        if (filter_byte) {
                            self.filters[current_row] = @intToEnum(Filter, buffer[i]);
                            filter_byte = false;
                            i += 1;
                        } else {
                            const len = @min(decompressed - i, row_size - current_byte);

                            @memcpy(self.buffer[current_byte_total .. current_byte_total + len], buffer[i .. i + len]);

                            current_byte += len;
                            current_byte_total += len;
                            i += len;

                            if (row_size == current_byte) {
                                current_row += 1;
                                current_byte = 0;
                                filter_byte = true;
                            }
                        }
                    }

                    cond = stream.avail_in > 0 or 0 == stream.avail_out;
                }
            }
        }

        fn fillImage(self: *const Info) void {
            const swizzle = self.swizzle;
            const invert = self.invert;
            const byte_compatible = self.byte_compatible;
            const buffer = self.buffer;

            switch (self.image) {
                .Byte1 => |image| {
                    if (byte_compatible) {
                        @memcpy(std.mem.sliceAsBytes(image.pixels), buffer[0..self.numPixelBytes()]);
                    } else {
                        var c: u32 = switch (swizzle) {
                            .W => 3,
                            else => 0,
                        };

                        if (c >= self.num_channels) {
                            c = 0;
                        }

                        var i: u32 = 0;
                        const len = @intCast(u32, self.width * self.height);
                        while (i < len) : (i += 1) {
                            const o = i * self.num_channels;

                            var color = buffer[o + c];
                            if (invert) {
                                color = 255 - color;
                            }

                            image.pixels[i] = color;
                        }
                    }
                },
                .Byte2 => |image| {
                    if (byte_compatible) {
                        @memcpy(std.mem.sliceAsBytes(image.pixels), buffer[0..self.numPixelBytes()]);
                    } else {
                        var i: u32 = 0;
                        const len = @intCast(u32, self.width * self.height);

                        if (.YX == swizzle) {
                            while (i < len) : (i += 1) {
                                const o = i * self.num_channels;
                                image.pixels[i] = Vec2b{ buffer[o + 1], buffer[o + 0] };
                            }
                        } else if (.YZ == swizzle and self.num_channels >= 3) {
                            while (i < len) : (i += 1) {
                                const o = i * self.num_channels;
                                image.pixels[i] = Vec2b{ buffer[o + 1], buffer[o + 2] };
                            }
                        } else {
                            while (i < len) : (i += 1) {
                                const o = i * self.num_channels;
                                image.pixels[i] = Vec2b{ buffer[o + 0], buffer[o + 1] };
                            }
                        }
                    }
                },
                .Byte3 => |image| {
                    if (byte_compatible) {
                        @memcpy(std.mem.sliceAsBytes(image.pixels), buffer[0..self.numPixelBytes()]);
                    } else {
                        var color = Pack3b.init1(0);

                        var i: u32 = 0;
                        const len = @intCast(u32, self.width * self.height);
                        while (i < len) : (i += 1) {
                            const o = i * self.num_channels;

                            var c: u32 = 0;
                            while (c < 3) : (c += 1) {
                                color.v[c] = buffer[o + c];
                            }

                            image.pixels[i] = color;
                        }
                    }
                },
                else => {},
            }
        }

        fn numPixelBytes(self: *const Info) u32 {
            const row_size = @intCast(u32, self.width) * self.num_channels;
            return row_size * @intCast(u32, self.height);
        }

        fn resolveFilter(self: *const Info) void {
            const height = @intCast(u32, self.height);
            const row_size = @intCast(u32, self.width) * self.num_channels;
            const bpp = self.bytes_per_pixel;

            var current_row_data = self.buffer;

            var row: u32 = 0;
            while (row < height) : (row += 1) {
                const filter = self.filters[row];

                const previous_row_data = current_row_data - row_size;

                switch (filter) {
                    .None => {},
                    .Sub => {
                        for (current_row_data[bpp..row_size], 0..) |*b, i| {
                            b.* +%= current_row_data[i];
                        }
                    },
                    .Up => {
                        for (current_row_data[0..row_size], 0..) |*b, i| {
                            b.* +%= previous_row_data[i];
                        }
                    },
                    .Average => {
                        for (current_row_data[0..bpp], 0..) |*b, i| {
                            b.* +%= previous_row_data[i] >> 1;
                        }

                        for (current_row_data[bpp..row_size], 0..) |*b, i| {
                            const p = @as(u32, previous_row_data[i + bpp]);
                            const a = @as(u32, current_row_data[i]);
                            b.* +%= @truncate(u8, (a + p) >> 1);
                        }
                    },
                    .Paeth => {
                        for (current_row_data[0..bpp], 0..) |*b, i| {
                            b.* +%= previous_row_data[i];
                        }

                        for (current_row_data[bpp..row_size], 0..) |*b, i| {
                            const p = previous_row_data[i + bpp];
                            b.* +%= paethPredictor(current_row_data[i], p, previous_row_data[i]);
                        }
                    },
                }

                current_row_data += row_size;
            }
        }

        fn paethPredictor(a: u8, b: u8, c: u8) u8 {
            const A = @intCast(i32, a);
            const B = @intCast(i32, b);
            const C = @intCast(i32, c);
            const p = A + B - C;
            const pa = std.math.absInt(p - A) catch unreachable;
            const pb = std.math.absInt(p - B) catch unreachable;
            const pc = std.math.absInt(p - C) catch unreachable;

            if (pa <= pb and pa <= pc) {
                return a;
            }

            if (pb <= pc) {
                return b;
            }

            return c;
        }
    };

    chunk: Chunk = .{},

    infos: [2]Info = .{ Info.init(), Info.init() },

    current_info: u32 = 0,

    pub fn deinit(self: *Reader, alloc: Allocator) void {
        self.infos[0].deinit(alloc);
        self.infos[1].deinit(alloc);
        self.chunk.deinit(alloc);
    }

    pub fn read(self: *Reader, alloc: Allocator, stream: *ReadStream, swizzle: Swizzle, invert: bool, threads: *Threads) !Image {
        var signature: [Signature.len]u8 = undefined;
        _ = try stream.read(&signature);

        if (!std.mem.eql(u8, &signature, &Signature)) {
            return Error.BadPNGSignature;
        }

        const info = &self.infos[self.current_info];

        while (self.handleChunk(alloc, stream, info)) {}

        const image = try info.allocateImage(alloc, swizzle, invert);

        if (threads.runningAsync()) {
            try info.process();
        } else {
            self.current_info = if (0 == self.current_info) 1 else 0;
            threads.runAsync(info, createImageAsync);
        }

        return image;
    }

    fn createImageAsync(context: ThreadContext) void {
        const info = @intToPtr(*Info, context);

        info.process() catch {};
    }

    fn handleChunk(self: *Reader, alloc: Allocator, stream: *ReadStream, info: *Info) bool {
        var length: u32 = 0;
        _ = stream.read(std.mem.asBytes(&length)) catch return false;

        length = @byteSwap(length);

        // Max chunk length according to spec
        if (length > 0x7FFFFFFF) {
            return false;
        }

        const chunk = &self.chunk;

        chunk.length = length;

        var chunk_type: u32 = 0;
        _ = stream.read(std.mem.asBytes(&chunk_type)) catch return false;

        // IHDR: 0x52444849
        if (0x52444849 == chunk_type) {
            readChunk(alloc, stream, chunk) catch return false;
            self.parseHeader(alloc, info) catch return false;

            return true;
        }

        // IDAT: 0x54414449
        if (0x54414449 == chunk_type) {
            if (info.num_chunks >= info.data_chunks.items.len) {
                info.data_chunks.append(alloc, .{}) catch return false;
            }

            const data_chunk = &info.data_chunks.items[info.num_chunks];
            data_chunk.length = length;
            readChunk(alloc, stream, data_chunk) catch return false;

            info.num_chunks += 1;

            return true;
        }

        // IEND: 0x444E4549
        if (0x444E4549 == chunk_type) {
            return false;
        }

        stream.seekBy(length + 4) catch return false;

        return true;
    }

    fn readChunk(alloc: Allocator, stream: *ReadStream, chunk: *Chunk) !void {
        try chunk.allocate(alloc);

        _ = try stream.read(chunk.data[0..chunk.length]);

        // crc32
        try stream.seekBy(4);
    }

    fn parseHeader(self: *Reader, alloc: Allocator, info: *Info) !void {
        const chunk = self.chunk;

        info.width = @intCast(i32, std.mem.readIntForeign(u32, chunk.data[0..4]));
        info.height = @intCast(i32, std.mem.readIntForeign(u32, chunk.data[4..8]));

        const depth = chunk.data[8];

        if (8 != depth) {
            return Error.PNGBitDepthNotSupported;
        }

        const color_type = @intToEnum(ColorType, chunk.data[9]);

        info.num_channels = switch (color_type) {
            .Grayscale => 1,
            .Truecolor => 3,
            .Truecolor_alpha => 4,
            else => 0,
        };

        if (0 == info.num_channels) {
            return Error.IndexedPNGNotSupperted;
        }

        info.bytes_per_pixel = info.num_channels;

        const interlace = chunk.data[12];
        if (interlace > 0) {
            return Error.InterlacedPNGNotSupported;
        }

        try info.allocate(alloc);
    }
};
