const img = @import("../../image.zig");
const Image = img.Image;
const ReadStream = @import("../../../file/read_stream.zig").ReadStream;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Pack3h = math.Pack3h;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;
const spectrum = base.spectrum;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Reader = struct {
    const Error = error{
        BadInitialToken,
        MissingFormatSpecifier,
        MissingImageSizeSpecifier,
        WrongScanlineWidth,
        BadScanlineData,
    };

    const Header = struct {
        width: u32,
        height: u32,
    };

    pub fn read(alloc: Allocator, stream: ReadStream) !Image {
        const header = try readHeader(stream);

        const dimensions = Vec2i{ @intCast(header.width), @intCast(header.height) };

        var image = try img.Half3.init(alloc, img.Description.init2D(dimensions));

        try readPixelsRLE(alloc, stream, header.width, header.height, &image);
        errdefer image.deinit(alloc);

        return Image{ .Half3 = image };
    }

    fn readHeader(stream: ReadStream) !Header {
        var buf: [128]u8 = undefined;

        {
            var writer: std.Io.Writer = .fixed(&buf);
            _ = try stream.streamDelimiter(&writer, '\n', .limited(buf.len));

            if (!std.mem.startsWith(u8, writer.buffered(), "#?")) {
                return Error.BadInitialToken;
            }
        }

        var format_specifier: bool = false;
        while (true) {
            var writer: std.Io.Writer = .fixed(&buf);
            _ = try stream.streamDelimiter(&writer, '\n', .limited(buf.len));
            const line = writer.buffered();

            if (0 == line.len or 0 == line[0]) {
                // blank lines signifies end of meta data header
                break;
            }

            if (std.mem.eql(u8, line, "FORMAT=32-bit_rle_rgbe")) {
                format_specifier = true;
            }
        }

        if (!format_specifier) {
            return Error.MissingFormatSpecifier;
        }

        var writer: std.Io.Writer = .fixed(&buf);
        _ = try stream.streamDelimiter(&writer, '\n', .limited(buf.len));
        var line = writer.buffered();

        var i = (std.mem.indexOfScalar(u8, line, ' ') orelse return Error.MissingImageSizeSpecifier) + 1;
        if (!std.mem.eql(u8, line[0..i], "-Y ")) {
            return Error.MissingImageSizeSpecifier;
        }

        line = line[i..];
        i = (std.mem.indexOfScalar(u8, line, ' ') orelse return Error.MissingImageSizeSpecifier);

        const height = std.fmt.parseInt(u32, line[0..i], 0) catch return Error.MissingImageSizeSpecifier;

        line = line[i + 1 ..];
        i = (std.mem.indexOfScalar(u8, line, ' ') orelse return Error.MissingImageSizeSpecifier) + 1;
        if (!std.mem.eql(u8, line[0..i], "+X ")) {
            return Error.MissingImageSizeSpecifier;
        }

        const width = std.fmt.parseInt(u32, line[i..], 0) catch return Error.MissingImageSizeSpecifier;

        return Header{ .width = width, .height = height };
    }

    fn readPixelsRLE(
        alloc: Allocator,
        stream: ReadStream,
        scanline_width: u32,
        num_scanlines: u32,
        image: *img.Half3,
    ) !void {
        if (scanline_width < 8 or scanline_width > 0x7fff) {
            return try readPixels(stream, scanline_width * num_scanlines, image, 0);
        }

        var offset: u32 = 0;

        var rgbe: [4]u8 = undefined;
        var buf: [2]u8 = undefined;

        var scanline_buffer = try alloc.alloc(u8, 4 * scanline_width);
        defer alloc.free(scanline_buffer);

        var s = num_scanlines;
        while (s > 0) : (s -= 1) {
            _ = try stream.read(&rgbe);

            if (rgbe[0] != 2 or rgbe[1] != 2 or (rgbe[2] & 0x80) != 0) {
                // this file is not run length encoded

                const color = rgbeTofloat3(rgbe);
                image.pixels[offset] = Pack3h.init3(
                    @floatCast(color.v[0]),
                    @floatCast(color.v[1]),
                    @floatCast(color.v[2]),
                );

                return try readPixels(stream, scanline_width * num_scanlines - 1, image, 1);
            }

            if ((@as(u32, rgbe[2]) << 8 | @as(u32, rgbe[3])) != scanline_width) {
                return Error.WrongScanlineWidth;
            }

            // read each of the four channels for the scanline into the buffer
            var c: u32 = 0;
            var index: u32 = 0;
            while (c < 4) : (c += 1) {
                const end = (c + 1) * scanline_width;

                while (index < end) {
                    _ = try stream.read(&buf);

                    if (buf[0] > 128) {
                        // a run of the same value
                        var count = @as(u32, buf[0]) - 128;
                        if (count == 0 or count > end - index) {
                            return Error.BadScanlineData;
                        }

                        while (count > 0) : (count -= 1) {
                            scanline_buffer[index] = buf[1];
                            index += 1;
                        }
                    } else {
                        // a non-run
                        var count = @as(u32, buf[0]);
                        if (count == 0 or count > end - index) {
                            return Error.BadScanlineData;
                        }

                        scanline_buffer[index] = buf[1];
                        index += 1;
                        count -= 1;

                        if (count > 0) {
                            _ = try stream.read(scanline_buffer[index .. index + count]);
                            index += count;
                        }
                    }
                }
            }

            // now convert data from buffer into floats
            var i: u32 = 0;
            while (i < scanline_width) : (i += 1) {
                rgbe[0] = scanline_buffer[i];
                rgbe[1] = scanline_buffer[i + scanline_width];
                rgbe[2] = scanline_buffer[i + 2 * scanline_width];
                rgbe[3] = scanline_buffer[i + 3 * scanline_width];

                const color = rgbeTofloat3(rgbe);
                image.pixels[offset] = Pack3h.init3(
                    @floatCast(color.v[0]),
                    @floatCast(color.v[1]),
                    @floatCast(color.v[2]),
                );

                offset += 1;
            }
        }
    }

    fn readPixels(stream: ReadStream, num_pixels: u32, image: *img.Half3, offset: u32) !void {
        var rgbe: [4]u8 = undefined;

        var i = num_pixels;
        var o = offset;
        while (i > 0) : (i -= 1) {
            _ = try stream.read(&rgbe);

            const color = rgbeTofloat3(rgbe);
            image.pixels[o] = Pack3h.init3(
                @floatCast(color.v[0]),
                @floatCast(color.v[1]),
                @floatCast(color.v[2]),
            );

            o += 1;
        }
    }

    // https://cbloomrants.blogspot.com/2020/06/widespread-error-in-radiance-hdr-rgbe.html
    fn rgbeTofloat3(rgbe: [4]u8) Pack3f {
        if (rgbe[3] > 0) {
            // nonzero pixel
            const f = std.math.scalbn(@as(f32, 1.0), @as(i32, rgbe[3]) - (128 + 8));

            const srgb = Vec4f{
                (@as(f32, @floatFromInt(rgbe[0])) + 0.5) * f,
                (@as(f32, @floatFromInt(rgbe[1])) + 0.5) * f,
                (@as(f32, @floatFromInt(rgbe[2])) + 0.5) * f,
                0.0,
            };

            return math.vec4fTo3f(spectrum.aces.sRGBtoAP1(srgb));
        }

        return Pack3f.init1(0.0);
    }
};
