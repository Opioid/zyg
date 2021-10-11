const std = @import("std");

pub const FileReadStream = struct {
    const Reader = std.io.BufferedReader(4096, std.fs.File.Reader);
    const Seeker = std.fs.File.SeekableStream;

    pub const Error = Reader.Error;

    reader: Reader = .{ .unbuffered_reader = undefined },
    seeker: Seeker = undefined,
    //   cur: u64,

    const Self = @This();

    pub fn setFile(self: *Self, file: std.fs.File) void {
        self.reader.unbuffered_reader = file.reader();
        self.seeker = file.seekableStream();
    }

    pub fn close(self: *Self) void {
        self.seeker.context.close();
    }

    pub fn seekTo(self: *Self, pos: u64) !void {
        self.reader.fifo.head = 0;
        self.reader.fifo.count = 0;
        //    self.cur = pos;
        return try self.seeker.seekTo(pos);
    }

    pub fn seekBy(self: *Self, count: u64) !void {
        const pos = (try self.seeker.getPos()) - self.reader.fifo.count;
        return try self.seekTo(pos + count);
    }
};
