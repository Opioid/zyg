const ReadStream = @import("read_stream.zig").ReadStream;

const std = @import("std");
const Allocator = std.mem.Allocator;

const mz = @cImport({
    @cInclude("miniz/miniz.h");
});

pub const GzipReadStream = struct {
    const Error = error{
        InputOutput,
        SystemResources,
        IsDir,
        OperationAborted,
        BrokenPipe,
        ConnectionResetByPeer,
        ConnectionTimedOut,
        NotOpenForReading,
        WouldBlock,
        AccessDenied,
        EndOfStream,
        Unexpected,
        StreamTooLong,
        OutOfMemory,
        InvalidGzipHeader,
        UnknownGzipCompressionAlgorithm,
        InitMZStreamFailed,
        InflateMZStreamFailed,
    };

    const SeekError = error{
        Unseekable,
        AccessDenied,
        Unexpected,
        SystemResources,
        ResetMZStreamFailed,
    } || Error;

    const Buffer_size = 8192;

    stream: ReadStream = undefined,

    // miniz
    z_stream: mz.mz_stream = undefined,

    data_start: u64 = undefined,

    buffer_head: u32 = undefined,
    buffer_count: u32 = undefined,

    buffer: [Buffer_size]u8 = undefined,
    read_buffer: [Buffer_size]u8 = undefined,

    const Self = @This();

    const Reader = std.io.Reader(*Self, Error, read);

    pub fn reader(self: *Self) Reader {
        return .{ .context = self };
    }

    pub fn close(self: *Self) void {
        _ = mz.mz_inflateEnd(&self.z_stream);

        self.stream.deinit();
    }

    pub fn setStream(self: *Self, stream: ReadStream) !void {
        self.stream = stream;

        var header: [10]u8 = undefined;
        _ = try self.stream.read(&header);

        if (0x1F != header[0] or 0x8B != header[1]) {
            return Error.InvalidGzipHeader;
        }

        if (8 != header[2]) {
            return Error.UnknownGzipCompressionAlgorithm;
        }

        if ((1 << 2 & header[3]) != 0) {
            // FEXTRA
            var n: [2]u8 = undefined;
            _ = try self.stream.read(&n);
            const len = @as(u64, n[0]) << 0 | @as(u64, n[1]) << 8;
            try self.stream.seekBy(len);
        }

        if ((1 << 3 & header[3]) != 0) {
            // FNAME
            try self.stream.skipUntilDelimiter(0);
        }

        if ((1 << 4 & header[3]) != 0) {
            // FCOMMENT
            try self.stream.skipUntilDelimiter(0);
        }

        if ((1 << 1 & header[3]) != 0) {
            // FRC
            try self.stream.seekBy(2);
        }

        self.data_start = try self.stream.getPos();
        self.buffer_head = 0;
        self.buffer_count = 0;

        return try self.initZstream();
    }

    pub fn read(self: *Self, dest: []u8) Error!usize {
        var dest_cur: u64 = 0;

        while (dest_cur < dest.len) {
            if (0 == self.buffer_count) {
                if (!try self.underflow()) {
                    break;
                }
            }

            const copy_len = @minimum(@intCast(u32, dest.len - dest_cur), self.buffer_count);

            const dest_end = dest_cur + copy_len;
            const source_end = self.buffer_head + copy_len;

            std.mem.copy(u8, dest[dest_cur..dest_end], self.buffer[self.buffer_head..source_end]);

            dest_cur += copy_len;

            self.buffer_head += copy_len;
            self.buffer_count -= copy_len;
        }

        return dest_cur;
    }

    pub fn seekTo(self: *Self, pos: u64) SeekError!void {
        const buffer_len = self.buffer_head + self.buffer_count;
        const buffer_start = self.z_stream.total_out - buffer_len;
        const buffer_offset = @intCast(i64, pos) - @intCast(i64, buffer_start);

        if (buffer_offset >= 0 and buffer_offset < buffer_len) {
            const d = @as(i64, self.buffer_head) - buffer_offset;
            self.buffer_head = @intCast(u32, buffer_offset);
            self.buffer_count = @intCast(u32, @as(i64, self.buffer_count) + d);
        } else {
            if (buffer_offset < 0) {
                try self.stream.seekTo(self.data_start);

                if (mz.MZ_OK != mz.mz_inflateReset(&self.z_stream)) {
                    return SeekError.ResetMZStreamFailed;
                }

                self.z_stream.avail_in = 0;
                self.z_stream.avail_out = 0;
            }

            while (self.z_stream.total_out < pos) {
                if (!(try self.underflow())) {
                    return SeekError.Unexpected;
                }
            }

            const bs = self.z_stream.total_out - (self.buffer_head + self.buffer_count);
            const bo = @intCast(u32, pos - bs);
            const d = self.buffer_head - bo;
            self.buffer_head = bo;
            self.buffer_count += d;
        }
    }

    pub fn seekBy(self: *Self, count: u64) SeekError!void {
        const cur = self.z_stream.total_out - self.buffer_count;

        return try self.stream.seekBy(cur + count);
    }

    fn initZstream(self: *Self) !void {
        self.z_stream.zalloc = null;
        self.z_stream.zfree = null;

        if (mz.MZ_OK != mz.mz_inflateInit2(&self.z_stream, -mz.MZ_DEFAULT_WINDOW_BITS)) {
            return Error.InitMZStreamFailed;
        }

        self.z_stream.avail_in = 0;
        self.z_stream.avail_out = 0;
    }

    fn underflow(self: *Self) !bool {
        var uncompressed_bytes: u32 = 0;

        while (0 == uncompressed_bytes) {
            if (0 == self.z_stream.avail_in) {
                const read_bytes = try self.stream.read(&self.read_buffer);

                self.z_stream.avail_in = @intCast(c_uint, read_bytes);
                self.z_stream.next_in = &self.read_buffer;
            }

            if (0 == self.z_stream.avail_out) {
                self.z_stream.avail_out = Buffer_size;
                self.z_stream.next_out = &self.buffer;

                self.buffer_head = 0;
                self.buffer_count = 0;
            }

            const avail_out = self.z_stream.avail_out;

            const status = mz.mz_inflate(&self.z_stream, mz.MZ_NO_FLUSH);
            if (status != mz.MZ_OK and status != mz.MZ_STREAM_END and status != mz.MZ_BUF_ERROR and status != mz.MZ_NEED_DICT) {
                return Error.InflateMZStreamFailed;
            }

            uncompressed_bytes = avail_out - self.z_stream.avail_out;

            if (0 == uncompressed_bytes and mz.MZ_STREAM_END == status) {
                return false;
            }
        }

        self.buffer_count += uncompressed_bytes;

        return true;
    }
};