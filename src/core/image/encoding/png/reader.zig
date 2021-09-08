const img = @import("../../image.zig");
const Image = img.Image;
const ReadStream = @import("../../../file/read_stream.zig").ReadStream;
const base = @import("base");
usingnamespace base.math;

const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("miniz/miniz.h");
});

const Signature = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };

pub const Reader = struct {
    const Error = error{
        BadPNGSignature,
        PNGBitDepthNotSupported,
        InterlacedPNGNotSupported,
        IndexedPNGNotSupperted,
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

    const Filter = enum { None, Sub, Up, Average, Path };

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

        num_channels: i32 = 0,
        bytes_per_pixel: i32 = 0,

        // parsing state
        current_filter: Filter = undefined,
        filter_byte: bool = undefined,
        current_byte: i32 = undefined,
        current_byte_total: i32 = undefined,

        // miniz
        stream: c.mz_stream = undefined,

        pub fn init() Info {
            var info = Info{};

            info.stream.zalloc = null;
            info.stream.zfree = null;

            return info;
        }

        pub fn deinit(self: *Info, alloc: *Allocator) void {
            _ = alloc;

            std.debug.print("Info.deinit()\n", .{});

            if (self.stream.zfree) |_| {
                std.debug.print("freelyfree\n", .{});
                _ = c.mz_inflateEnd(&self.stream);
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
            //&& parse_header(chunk, info);
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

    fn parseHeader(alloc: *Allocator, chunk: *Chunk, info: *Info) !void {
        _ = alloc;

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
    }
};
