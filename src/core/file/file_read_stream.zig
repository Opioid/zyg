const std = @import("std");

pub const FileReadStream = struct {
    buffer: [4096]u8,
    reader: std.fs.File.Reader,

    const Self = @This();

    pub fn setFile(self: *Self, file: std.fs.File) void {
        self.reader = file.reader(&self.buffer);
    }

    pub fn close(self: *Self) void {
        self.reader.file.close();
    }
};
