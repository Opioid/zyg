const ReadStream = @import("read_stream.zig").ReadStream;

const std = @import("std");

pub const Type = enum { Undefined, EXR, GZIP, PNG, RGBE, SUB, ZSTD };

pub fn queryType(stream: *ReadStream) Type {
    var header: [4]u8 = undefined;
    _ = stream.read(&header) catch {
        return .Undefined;
    };

    stream.seekTo(0) catch {};

    if (std.mem.startsWith(u8, &header, "\x1f\x8b")) {
        return .GZIP;
    }

    if (std.mem.startsWith(u8, &header, "SUB\x00")) {
        return .SUB;
    }

    return .Undefined;
}
