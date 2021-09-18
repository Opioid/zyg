const std = @import("std");

pub const ReadStream = struct {
    const Reader = std.io.BufferedReader(4096, std.fs.File.Reader);
    const Seeker = std.fs.File.SeekableStream;

    const ReadError = Reader.Error;
    const SeekError = Seeker.SeekError;

    file: std.fs.File,
    reader: Reader,
    seeker: Seeker,
    //   cur: u64,

    const Self = @This();

    pub fn init(file: std.fs.File) ReadStream {
        return .{
            .file = file,
            .reader = Reader{ .unbuffered_reader = file.reader() },
            .seeker = file.seekableStream(),
            //       .cur = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
    }

    pub fn read(self: *Self, dest: []u8) ReadError!usize {
        return try self.reader.read(dest);
    }

    pub fn readUntilDelimiter(self: *Self, buf: []u8, delimiter: u8) ![]u8 {
        return try self.reader.reader().readUntilDelimiter(buf, delimiter);
    }

    pub fn seekTo(self: *Self, pos: u64) SeekError!void {
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
