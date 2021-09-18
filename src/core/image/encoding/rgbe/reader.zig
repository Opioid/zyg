const img = @import("../../image.zig");
const Image = img.Image;
const ReadStream = @import("../../../file/read_stream.zig").ReadStream;
const math = @import("base").math;
const Vec2i = math.Vec2i;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Reader = struct {
    const Error = error{
        BadInitialToken,
        MissingFormatSpecifier,
        MissingImageSizeSpecifier,
    };

    const Header = struct {
        width: i32,
        height: i32,
    };

    pub fn read(alloc: *Allocator, stream: *ReadStream) !Image {
        _ = alloc;
        _ = stream;

        const header = try readHeader(stream);

        const dimensions = Vec2i.init2(header.width, header.height);

        var image = try img.Half3.init(alloc, img.Description.init2D(dimensions));

        return Image{ .Half3 = image };
    }

    fn readHeader(stream: *ReadStream) !Header {
        var buf: [128]u8 = undefined;
        {
            const line = try stream.readUntilDelimiter(&buf, '\n');

            if (!std.mem.startsWith(u8, line, "#?")) {
                return Error.BadInitialToken;
            }
        }

        var format_specifier: bool = false;
        while (true) {
            const line = try stream.readUntilDelimiter(&buf, '\n');
            if (0 == line.len or 0 == line[0]) {
                // blank lines signifies end of meta data header
                break;
            }

            if (!std.mem.startsWith(u8, line, "FORMAT=32-bit_rle_rgbe")) {
                format_specifier = true;
            }
        }

        if (!format_specifier) {
            return Error.MissingFormatSpecifier;
        }

        // var header: Header = undefined;
        // const line = try stream.readUntilDelimiter(&buf, '\n');

        return Error.MissingImageSizeSpecifier;
    }
};
