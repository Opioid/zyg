const std = @import("std");
const Io = std.Io;

pub const FileReadStream = struct {
    buffer: [4096]u8,
    reader: Io.File.Reader,

    const Self = @This();

    pub fn setFile(self: *Self, io: Io, file: std.fs.File) void {
        self.reader = file.reader(io, &self.buffer);
    }

    pub fn close(self: *Self) void {
        self.reader.file.close(self.reader.io);
    }
};
