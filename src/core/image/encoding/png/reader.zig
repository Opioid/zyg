const img = @import("../../image.zig");
const Image = img.Image;
const ReadStream = @import("../../../file/read_stream.zig").ReadStream;
const math = @import("base").math;
const Vec2i = math.Vec2i;

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

        pub fn allocate(self: *Chunk, alloc: *Allocator) !void {
            if (self.length >= self.data.len) {
                self.data = try alloc.realloc(self.data, self.length);
            }
        }

        pub fn deinit(self: *Chunk, alloc: *Allocator) void {
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

        // parsing state
        current_filter: Filter = undefined,
        filter_byte: bool = undefined,
        current_byte: u32 = undefined,
        current_byte_total: u32 = undefined,

        buffer: []u8 = &.{},
        current_row_data: [*]u8 = undefined,
        previous_row_data: [*]u8 = undefined,

        // miniz
        stream: mz.mz_stream = undefined,

        pub fn init() Info {
            var info = Info{};

            info.stream.zalloc = null;
            info.stream.zfree = null;

            return info;
        }

        pub fn deinit(self: *Info, alloc: *Allocator) void {
            std.debug.print("Info.deinit()\n", .{});

            if (self.stream.zfree) |_| {
                std.debug.print("freelyfree\n", .{});
                _ = mz.mz_inflateEnd(&self.stream);
            }

            alloc.free(self.buffer);
        }

        pub fn allocate(self: *Info, alloc: *Allocator) !void {
            const row_size = @intCast(u32, self.width) * self.num_channels;
            const buffer_size = row_size * @intCast(u32, self.height);
            const num_bytes = buffer_size + 2 * row_size;

            if (self.buffer.len < num_bytes) {
                self.buffer = try alloc.realloc(self.buffer, num_bytes);
            }

            self.current_row_data = self.buffer.ptr + buffer_size;
            self.previous_row_data = self.current_row_data + buffer_size;

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
    };

    chunk: Chunk = .{},

    info: Info = Info.init(),

    pub fn deinit(self: *Reader, alloc: *Allocator) void {
        self.info.deinit(alloc);
        self.chunk.deinit(alloc);
    }

    pub fn read(self: *Reader, alloc: *Allocator, stream: *ReadStream) !Image {
        _ = self;
        _ = alloc;

        var signature: [Signature.len]u8 = undefined;

        _ = try stream.read(&signature);

        if (!std.mem.eql(u8, &signature, &Signature)) {
            return Error.BadPNGSignature;
        }

        while (handleChunk(alloc, stream, &self.chunk, &self.info)) {}

        std.debug.print("We got here\n", .{});

        return try createImage(alloc, self.info);
    }

    fn createImage(alloc: *Allocator, info: Info) !Image {
        const num_channels = info.num_channels;

        const dimensions = Vec2i.init2(info.width, info.height);

        if (3 == num_channels) {
            var image = try img.Byte3.init(alloc, img.Description.init2D(dimensions));

            return Image{ .Byte3 = image };
        }

        return Error.UnexpectedError;
    }

    fn handleChunk(alloc: *Allocator, stream: *ReadStream, chunk: *Chunk, info: *Info) bool {
        var length: u32 = 0;
        _ = stream.read(std.mem.asBytes(&length)) catch return false;

        length = @byteSwap(u32, length);

        // Max chunk length according to spec
        if (length > 0x7FFFFFFF) {
            return false;
        }

        chunk.length = length;

        var chunk_type: u32 = 0;
        _ = stream.read(std.mem.asBytes(&chunk_type)) catch return false;

        // IHDR: 0x52444849
        if (0x52444849 == chunk_type) {
            readChunk(alloc, stream, chunk) catch return false;
            parseHeader(alloc, chunk, info) catch return false;

            return true;
        }

        // IDAT: 0x54414449
        if (0x54414449 == chunk_type) {
            readChunk(alloc, stream, chunk) catch return false;
            parseData(alloc, chunk, info) catch return false;

            return true;
        }

        // IEND: 0x444E4549
        if (0x444E4549 == chunk_type) {
            std.debug.print("end chunk\n", .{});
            return false;
        }

        stream.seekBy(length + 4) catch return false;

        return true;
    }

    fn readChunk(alloc: *Allocator, stream: *ReadStream, chunk: *Chunk) !void {
        try chunk.allocate(alloc);

        _ = try stream.read(chunk.data[0..chunk.length]);

        // crc32
        try stream.seekBy(4);
    }

    fn parseHeader(alloc: *Allocator, chunk: *const Chunk, info: *Info) !void {
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

        info.current_filter = .None;
        info.filter_byte = true;
        info.current_byte = 0;
        info.current_byte_total = 0;

        try info.allocate(alloc);
    }

    fn parseData(alloc: *Allocator, chunk: *const Chunk, info: *Info) !void {
        _ = alloc;
        _ = chunk;
        _ = info;

        const buffer_size = 8192;
        var buffer: [buffer_size]u8 = undefined;

        info.stream.next_in = chunk.data.ptr;
        info.stream.avail_in = chunk.length;

        const row_size = @intCast(u32, info.width) * info.num_channels;

        var cond = true;
        while (cond) {
            info.stream.next_out = &buffer;
            info.stream.avail_out = buffer_size;

            const status = mz.mz_inflate(&info.stream, mz.MZ_NO_FLUSH);
            if (status != mz.MZ_OK and status != mz.MZ_STREAM_END and status != mz.MZ_BUF_ERROR and status != mz.MZ_NEED_DICT) {
                return Error.InflateMZStreamFailed;
            }

            const decompressed = buffer_size - info.stream.avail_out;
            for (buffer[0..decompressed]) |b| {
                if (info.filter_byte) {
                    info.current_filter = @intToEnum(Filter, b);
                    info.filter_byte = false;
                } else {
                    const r = filter(b, info.current_filter, info);
                    info.current_row_data[info.current_byte] = r;
                    info.buffer[info.current_byte_total] = r;

                    info.current_byte += 1;
                    info.current_byte_total += 1;

                    if (row_size == info.current_byte) {
                        info.current_byte = 0;
                        std.mem.swap([*]u8, &info.current_row_data, &info.previous_row_data);
                        info.filter_byte = true;
                    }
                }
            }

            cond = info.stream.avail_in > 0 or 0 == info.stream.avail_out;
        }
    }

    fn filter(byte: u8, f: Filter, info: *const Info) u8 {
        return switch (f) {
            .None => byte,
            .Sub => byte + raw(@intCast(i32, info.current_byte) - @intCast(i32, info.bytes_per_pixel), info),
            .Up => byte + prior(@intCast(i32, info.current_byte), info),
            .Average => byte + average(
                raw(@intCast(i32, info.current_byte) - @intCast(i32, info.bytes_per_pixel), info),
                prior(@intCast(i32, info.current_byte), info),
            ),
            .Paeth => byte + paethPredictor(
                raw(@intCast(i32, info.current_byte) - @intCast(i32, info.bytes_per_pixel), info),
                prior(@intCast(i32, info.current_byte), info),
                prior(@intCast(i32, info.current_byte) - @intCast(i32, info.bytes_per_pixel), info),
            ),
        };
    }

    fn raw(column: i32, info: *const Info) u8 {
        if (column < 0) {
            return 0;
        }

        return info.current_row_data[@intCast(u32, column)];
    }

    fn prior(column: i32, info: *const Info) u8 {
        if (column < 0) {
            return 0;
        }

        return info.previous_row_data[@intCast(u32, column)];
    }

    fn average(a: u8, b: u8) u8 {
        return @truncate(u8, (@intCast(u32, a) + @intCast(u32, b)) >> 1);
    }

    fn paethPredictor(a: u8, b: u8, c: u8) u8 {
        _ = a;
        _ = b;
        _ = c;
        return 0;
        // const A = @intCast(i32, a);
        // const B = @intCast(i32, b);
        // const C = @intCast(i32, c);
        // const p = A + B - C;
        // const pa = std.math.abs(p - A);
        // const pb = std.math.abs(p - B);
        // const pc = std.math.abs(p - C);

        // if (pa <= pb and pa <= pc) {
        //     return a;
        // }

        // if (pb <= pc) {
        //     return b;
        // }

        // return c;
    }
};
