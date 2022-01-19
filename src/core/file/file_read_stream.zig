const std = @import("std");

pub const FileReadStream = struct {
    const Reader = std.io.BufferedReader(4096, std.fs.File.Reader);
    const Seeker = std.fs.File.SeekableStream;

    reader: Reader = .{ .unbuffered_reader = undefined },
    seeker: Seeker = undefined,

    const Self = @This();

    pub fn setFile(self: *Self, file: std.fs.File) void {
        self.reader.fifo.head = 0;
        self.reader.fifo.count = 0;
        self.reader.unbuffered_reader = file.reader();
        self.seeker = file.seekableStream();
    }

    pub fn close(self: *Self) void {
        self.seeker.context.close();
    }

    pub fn seekTo(self: *Self, pos: u64) !void {
        // // This won't work, befause Fifo.discard() overwrites the buffer content!
        // const buffer_len = self.reader.fifo.head + self.reader.fifo.count;
        // const buffer_start = (try self.seeker.getPos()) - buffer_len;
        // const buffer_offset = @intCast(i64, pos) - @intCast(i64, buffer_start);

        // if (buffer_offset >= 0 and buffer_offset < buffer_len) {
        //     const d = @intCast(i64, self.reader.fifo.head) - buffer_offset;
        //     self.reader.fifo.head = @intCast(usize, buffer_offset);
        //     self.reader.fifo.count = @intCast(usize, @intCast(i64, self.reader.fifo.count) + d);
        // } else {
        self.reader.fifo.head = 0;
        self.reader.fifo.count = 0;
        try self.seeker.seekTo(pos);
        // }
    }

    pub fn seekBy(self: *Self, count: u64) !void {
        const cur = (try self.seeker.getPos()) - self.reader.fifo.count;
        try self.seekTo(cur + count);
    }
};
