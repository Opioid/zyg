const ReadStream = @import("read_stream.zig").ReadStream;

const std = @import("std");

pub const Type = enum {
    Undefined,
    EXR,
    GZIP,
    IES,
    PNG,
    RGBE,
    SUB,
    ZSTD,
};

pub fn queryType(stream: *ReadStream) Type {
    var header: [4]u8 = undefined;
    _ = stream.read(&header) catch {
        return .Undefined;
    };

    stream.seekTo(0) catch {};

    if (std.mem.startsWith(u8, &header, "\x76\x2F\x31\x01")) {
        return .EXR;
    }

    if (std.mem.startsWith(u8, &header, "\x1f\x8b")) {
        return .GZIP;
    }

    if (std.mem.startsWith(u8, &header, "IES")) {
        return .IES;
    }

    if (std.mem.startsWith(u8, &header, "\x89PNG")) {
        return .PNG;
    }

    if (std.mem.startsWith(u8, &header, "#?")) {
        return .RGBE;
    }

    if (std.mem.startsWith(u8, &header, "SUB\x00")) {
        return .SUB;
    }

    return .Undefined;
}
