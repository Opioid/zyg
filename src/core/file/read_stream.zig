const std = @import("std");

pub const ReadStream = struct {
    const Reader = std.io.BufferedReader(4096, std.fs.File.Reader);
    const Seeker = std.fs.File.SeekableStream;

    const ReadError = Reader.Error;
    const SeekError = Seeker.SeekError;

    file: std.fs.File,
    reader: Reader,
    seeker: Seeker,

    const Self = @This();

    pub fn init(file: std.fs.File) ReadStream {
        return .{
            .file = file,
            .reader = Reader{ .unbuffered_reader = file.reader() },
            .seeker = file.seekableStream(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
    }

    pub fn read(self: *Self, dest: []u8) ReadError!usize {
        return try self.reader.read(dest);
    }

    pub fn seekTo(self: *Self, pos: u64) SeekError!void {
        self.reader.fifo.head = 0;
        self.reader.fifo.count = 0;
        return try self.seeker.seekTo(pos);
    }
};
