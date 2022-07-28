const img = @import("../../image.zig");
const Image = img.Image;
const ReadStream = @import("../../../file/read_stream.zig").ReadStream;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Reader = struct {
    const Error = error{
        BadInitialToken,
        NotImplemented,
    };

    pub fn read(alloc: Allocator, stream: *ReadStream) !Image {
        var buf: [256]u8 = undefined;

        {
            const line = try stream.readUntilDelimiter(&buf, '\n');

            if (!std.mem.startsWith(u8, line, "IES")) {
                return Error.BadInitialToken;
            }
        }

        while (true) {
            const line = try stream.readUntilDelimiter(&buf, '\n');

            if (std.mem.startsWith(u8, line, "TILT=NONE")) {
                break;
            }
        }

        {
            const line = try stream.readUntilDelimiter(&buf, '\n');

            std.debug.print("{s}\n", .{line});
        }

        _ = alloc;

        std.debug.print("We totally want to read a IES file\n", .{});

        return Error.NotImplemented;
    }
};
