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

    pub fn deinit(self: Self) void {
        switch (self) {
            .File => |s| s.close(),
            .Gzip => |s| s.close(),
        }
    }

    pub fn read(self: Self, dest: []u8) !usize {
        return switch (self) {
            .File => |s| try s.reader.interface.readSliceShort(dest),
            .Gzip => |s| try s.read(dest),
        };
    }

    pub fn readAlloc(self: Self, alloc: Allocator) ![]u8 {
        return switch (self) {
            .File => |s| try s.reader.interface.allocRemaining(alloc, .unlimited),
            .Gzip => |s| try s.reader().readAllAlloc(alloc, std.math.maxInt(u64)),
        };
    }

    pub fn streamDelimiter(self: Self, writer: *std.io.Writer, delimiter: u8, limit: std.Io.Limit) !usize {
        return switch (self) {
            .File => |s| {
                const count = try s.reader.interface.streamDelimiterLimit(writer, delimiter, limit);
                s.reader.interface.toss(1);
                return count + 1;
            },
            .Gzip => Error.NotImplemented,
        };
    }

    pub fn discardDelimiter(self: Self, delimiter: u8) !usize {
        return switch (self) {
            .File => |s| try s.reader.interface.discardDelimiterInclusive(delimiter),
            .Gzip => Error.NotImplemented,
        };
    }

    pub fn getPos(self: Self) u64 {
        return switch (self) {
            .File => |s| s.reader.logicalPos(),
            .Gzip => 0,
        };
    }

    pub fn seekTo(self: Self, pos: u64) !void {
        return switch (self) {
            .File => |s| try s.reader.seekTo(pos),
            .Gzip => |s| try s.seekTo(pos),
        };
    }

    pub fn discard(self: Self, count: usize) !void {
        return switch (self) {
            .File => |s| try s.reader.interface.discardAll(count),
            .Gzip => |s| try s.discard(count),
        };
    }
};
