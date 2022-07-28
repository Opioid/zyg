const img = @import("../../image.zig");
const Image = img.Image;
const ReadStream = @import("../../../file/read_stream.zig").ReadStream;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Reader = struct {
    const Error = error{
        NotImplemented,
    };

    pub fn read(alloc: Allocator, stream: *ReadStream) !Image {
        _ = alloc;
        _ = stream;

        std.debug.print("We totally want to read a IES file\n", .{});

        return Error.NotImplemented;
    }
};
