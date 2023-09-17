const FileStream = @import("file_read_stream.zig").FileReadStream;
const GzipStream = @import("gzip_read_stream.zig").GzipReadStream;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ReadStream = union(enum) {
    const Error = error{
        NotImplemented,
    };

    File: *FileStream,
    Gzip: *GzipStream,

    const Self = @This();

    pub fn initFile(stream: *FileStream) Self {
        return .{ .File = stream };
    }

    pub fn initGzip(stream: *GzipStream) Self {
        return .{ .Gzip = stream };
    }

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .File => |s| s.close(),
            .Gzip => |s| s.close(),
        }
    }

    pub fn read(self: Self, dest: []u8) !usize {
        return switch (self) {
            .File => |s| try s.reader.reader().readAll(dest),
            .Gzip => |s| try s.read(dest),
        };
    }

    pub fn readAll(self: Self, alloc: Allocator) ![]u8 {
        return switch (self) {
            .File => |s| try s.reader.reader().readAllAlloc(alloc, std.math.maxInt(u64)),
            .Gzip => |s| try s.reader().readAllAlloc(alloc, std.math.maxInt(u64)),
        };
    }

    pub fn streamUntilDelimiter(self: Self, writer: anytype, delimiter: u8, max_size: ?usize) !void {
        return switch (self) {
            .File => |s| try s.reader.reader().streamUntilDelimiter(writer, delimiter, max_size),
            .Gzip => |s| try s.reader().streamUntilDelimiter(writer, delimiter, max_size),
        };
    }

    pub fn skipUntilDelimiter(self: Self, delimiter: u8) !void {
        return switch (self) {
            .File => |s| try s.reader.reader().skipUntilDelimiterOrEof(delimiter),
            .Gzip => Error.NotImplemented,
        };
    }

    pub fn getPos(self: Self) !u64 {
        return switch (self) {
            .File => |s| try s.seeker.getPos(),
            .Gzip => Error.NotImplemented,
        };
    }

    pub fn seekTo(self: Self, pos: u64) !void {
        return switch (self) {
            .File => |s| try s.seekTo(pos),
            .Gzip => |s| try s.seekTo(pos),
        };
    }

    pub fn seekBy(self: Self, count: u64) !void {
        return switch (self) {
            .File => |s| try s.seekBy(count),
            .Gzip => |s| try s.seekBy(count),
        };
    }
};
