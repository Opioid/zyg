const exr = @import("exr.zig");
const img = @import("../../image.zig");
const Image = img.Image;
const Swizzle = img.Swizzle;
const ReadStream = @import("../../../file/read_stream.zig").ReadStream;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Pack3h = math.Pack3h;
const Pack3f = math.Pack3f;
const Pack4i = math.Pack4i;
const Pack4h = math.Pack4h;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Pack4f = math.Pack4f;
const spectrum = base.spectrum;

const std = @import("std");
const Allocator = std.mem.Allocator;

const mz = @cImport({
    @cInclude("miniz/miniz.h");
});

pub const Reader = struct {
    const Error = error{
        BadEXRSignature,
        DataWindowNotSubsetOfDisplayWindow,
        NoChannels,
        Exactly3ChannelsSupported,
        MixedChannelFormats,
        NotZipCompression,
        MZUncompressFailed,
        IncompatibleContent,
    };

    const Header = struct {
        width: u32,
        height: u32,
    };

    pub fn read(alloc: Allocator, stream: ReadStream, swizzle: Swizzle, color: bool) !Image {
        var signature: [exr.Signature.len]u8 = undefined;
        _ = try stream.read(&signature);

        if (!std.mem.eql(u8, &signature, &exr.Signature)) {
            return Error.BadEXRSignature;
        }

        // Skip version
        try stream.seekBy(exr.Signature.len);

        var name_buf: [128]u8 = undefined;
        var type_buf: [128]u8 = undefined;

        var name_fbs = std.io.fixedBufferStream(&name_buf);
        var type_fbs = std.io.fixedBufferStream(&type_buf);

        var channels = try Channels.init(alloc);
        defer channels.deinit(alloc);

        var compression = exr.Compression.Undefined;

        var data_window: Vec4i = @splat(0);
        var display_window: Vec4i = @splat(0);

        while (true) {
            name_fbs.reset();
            try stream.streamUntilDelimiter(name_fbs.writer(), '\x00', name_buf.len);
            const attribute_name = name_fbs.getWritten();

            if (0 == attribute_name.len) {
                break;
            }

            type_fbs.reset();
            try stream.streamUntilDelimiter(type_fbs.writer(), '\x00', type_buf.len);
            const attribute_type = type_fbs.getWritten();

            var attribute_size: u32 = undefined;
            _ = try stream.read(std.mem.asBytes(&attribute_size));

            if (std.mem.eql(u8, attribute_type, "box2i")) {
                var box: Pack4i = undefined;
                _ = try stream.read(std.mem.asBytes(&box));

                if (std.mem.eql(u8, attribute_name, "dataWindow")) {
                    data_window = box.v;
                } else if (std.mem.eql(u8, attribute_name, "displayWindow")) {
                    display_window = box.v;
                }
            } else if (std.mem.eql(u8, attribute_type, "chlist")) {
                try channels.read(alloc, stream);
            } else if (std.mem.eql(u8, attribute_type, "compression")) {
                _ = try stream.read(std.mem.asBytes(&compression));
            } else {
                try stream.seekBy(attribute_size);
            }
        }

        if (data_window[0] < display_window[0] or data_window[1] < display_window[1] or
            data_window[2] > display_window[2] or data_window[3] > display_window[3])
        {
            return Error.DataWindowNotSubsetOfDisplayWindow;
        }

        if (0 == channels.channels.items.len) {
            return Error.NoChannels;
        }

        if (!channels.singleFormat()) {
            return Error.MixedChannelFormats;
        }

        if (.ZIP != compression) {
            return Error.NotZipCompression;
        }

        return try readZip(alloc, stream, data_window, display_window, channels, swizzle, color);
    }

    fn readZip(
        alloc: Allocator,
        stream: ReadStream,
        data_window: Vec4i,
        display_window: Vec4i,
        channels: Channels,
        swizzle: Swizzle,
        color: bool,
    ) !Image {
        var num_channels: u32 = switch (swizzle) {
            .X, .W => 1,
            .XY, .YX, .YZ => 2,
            .XYZ => 3,
            .XYZW => 4,
        };

        const file_num_channels = @as(u32, @intCast(channels.channels.items.len));
        num_channels = @min(num_channels, file_num_channels);

        const data_xy = Vec2i{ data_window[0], data_window[1] };
        const data_zw = Vec2i{ data_window[2], data_window[3] };
        const data_dim = (data_zw - data_xy) + @as(Vec2i, @splat(1));

        const width = @as(u32, @intCast(data_dim[0]));
        const height = @as(u32, @intCast(data_dim[1]));

        const rows_per_block = exr.Compression.ZIP.numScanlinesPerBlock();
        const row_blocks = exr.Compression.ZIP.numScanlineBlocks(height);

        const bytes_per_pixel = channels.bytesPerPixel();
        const bytes_per_row = width * bytes_per_pixel;

        const bytes_per_row_block = bytes_per_row * rows_per_block;

        try stream.seekBy(row_blocks * 8);

        var buffer = try alloc.allocWithOptions(u8, bytes_per_row_block, 4, null);
        defer alloc.free(buffer);
        var uncompressed = try alloc.alloc(u8, bytes_per_row_block);
        defer alloc.free(uncompressed);

        const display_xy = Vec2i{ display_window[0], display_window[1] };
        const display_zw = Vec2i{ display_window[2], display_window[3] };
        const display_dim = (display_zw - display_xy) + @as(Vec2i, @splat(1));

        const display_width = @as(u32, @intCast(display_dim[0]));
        const display_height = @as(u32, @intCast(display_dim[1]));

        const half = .Half == channels.channels.items[0].format;
        const desc = img.Description.init2D(display_dim);

        var image = switch (num_channels) {
            4 => if (half)
                Image{ .Half4 = try img.Half4.init(alloc, desc) }
            else
                Image{ .Float4 = try img.Float4.init(alloc, desc) },
            else => if (half)
                Image{ .Half3 = try img.Half3.init(alloc, desc) }
            else
                Image{ .Float3 = try img.Float3.init(alloc, desc) },
        };

        errdefer image.deinit(alloc);

        var i: u32 = 0;
        while (i < row_blocks) : (i += 1) {
            var row: u32 = undefined;
            _ = try stream.read(std.mem.asBytes(&row));

            var size: u32 = undefined;
            _ = try stream.read(std.mem.asBytes(&size));

            _ = try stream.read(buffer[0..size]);

            const num_rows_here = @min(display_height - row, rows_per_block);
            const num_pixels_here = num_rows_here * width;

            if (size < bytes_per_row_block) {
                var uncompressed_size: c_ulong = bytes_per_row_block;
                if (mz.MZ_OK != mz.uncompress(uncompressed.ptr, &uncompressed_size, buffer.ptr, size)) {
                    return Error.MZUncompressFailed;
                }

                const uncompressed_here = uncompressed[0 .. num_pixels_here * bytes_per_pixel];

                reconstructScalar(uncompressed_here);
                interleaveScalar(uncompressed_here, buffer.ptr);
            }

            switch (image) {
                .Half3 => |half3| {
                    const halfs = @as([*]const f16, @ptrCast(buffer.ptr));

                    var y: u32 = 0;
                    while (y < num_rows_here) : (y += 1) {
                        const o = file_num_channels * y * width;

                        var p = (row + y) * display_width + @as(u32, @intCast(data_window[0]));
                        var x: u32 = 0;
                        while (x < width) : (x += 1) {
                            const r = halfs[o + 2 * width + x];
                            const g = halfs[o + 1 * width + x];
                            const b = halfs[o + 0 * width + x];

                            if (color) {
                                const rgbf = math.vec3hTo4f(Pack3h.init3(r, g, b));
                                half3.pixels[p] = math.vec4fTo3h(spectrum.sRGBtoAP1(rgbf));
                            } else {
                                half3.pixels[p] = Pack3h.init3(r, g, b);
                            }

                            p += 1;
                        }
                    }
                },
                .Float3 => |float3| {
                    const floats = @as([*]const f32, @ptrCast(buffer.ptr));

                    var y: u32 = 0;
                    while (y < num_rows_here) : (y += 1) {
                        const o = file_num_channels * y * width;

                        var p = (row + y) * display_width + @as(u32, @intCast(data_window[0]));
                        var x: u32 = 0;
                        while (x < width) : (x += 1) {
                            const r = floats[o + 2 * width + x];
                            const g = floats[o + 1 * width + x];
                            const b = floats[o + 0 * width + x];

                            if (color) {
                                float3.pixels[p] = math.vec4fTo3f(spectrum.sRGBtoAP1(.{ r, g, b, 0.0 }));
                            } else {
                                float3.pixels[p] = Pack3f.init3(r, g, b);
                            }

                            p += 1;
                        }
                    }
                },
                .Half4 => |half4| {
                    const halfs = @as([*]const f16, @ptrCast(buffer.ptr));

                    var y: u32 = 0;
                    while (y < num_rows_here) : (y += 1) {
                        const o = file_num_channels * y * width;

                        var p = row * display_width + @as(u32, @intCast(data_window[0]));
                        var x: u32 = 0;
                        while (x < width) : (x += 1) {
                            const r = halfs[o + 3 * width + x];
                            const g = halfs[o + 2 * width + x];
                            const b = halfs[o + 1 * width + x];
                            const a = halfs[o + 0 * width + x];

                            if (color) {
                                const ap = spectrum.sRGBtoAP1(.{ r, g, b, 0.0 });
                                const rgbf = Vec4f{ ap[0], ap[1], ap[2], a };
                                half4.pixels[p] = math.vec4fTo4h(rgbf);
                            } else {
                                const rgbf = Vec4f{ r, g, b, a };
                                half4.pixels[p] = math.vec4fTo4h(rgbf);
                            }

                            p += 1;
                        }
                    }
                },
                .Float4 => |float4| {
                    const floats = @as([*]const f32, @ptrCast(buffer.ptr));

                    var y: u32 = 0;
                    while (y < num_rows_here) : (y += 1) {
                        const o = file_num_channels * y * width;

                        var p = row * display_width + @as(u32, @intCast(data_window[0]));
                        var x: u32 = 0;
                        while (x < width) : (x += 1) {
                            const a = floats[o + 3 * width + x];
                            const r = floats[o + 2 * width + x];
                            const g = floats[o + 1 * width + x];
                            const b = floats[o + 0 * width + x];

                            if (color) {
                                const ap = spectrum.sRGBtoAP1(.{ r, g, b, 0.0 });
                                float4.pixels[p] = Pack4f.init4(ap[0], ap[1], ap[2], a);
                            } else {
                                float4.pixels[p] = Pack4f.init4(r, g, b, a);
                            }

                            p += 1;
                        }
                    }
                },
                else => {},
            }
        }

        return image;
    }
};

fn reconstructScalar(buf: []u8) void {
    var t: usize = 1;

    while (t < buf.len) : (t += 1) {
        const d = @as(u32, @intCast(buf[t - 1])) + @as(u32, @intCast(buf[t])) -% 128;
        buf[t] = @truncate(d);
    }
}

fn interleaveScalar(source: []const u8, out: [*]u8) void {
    var t1: usize = 0;
    var t2 = (source.len + 1) / 2;

    var s: usize = 0;
    const stop = source.len;

    while (true) {
        if (s < stop) {
            out[s] = source[t1];
            s += 1;
            t1 += 1;
        } else {
            break;
        }

        if (s < stop) {
            out[s] = source[t2];
            s += 1;
            t2 += 1;
        } else {
            break;
        }
    }
}

const Channels = struct {
    channels: std.ArrayListUnmanaged(exr.Channel),

    pub fn init(alloc: Allocator) !Channels {
        return Channels{ .channels = try std.ArrayListUnmanaged(exr.Channel).initCapacity(alloc, 4) };
    }

    pub fn deinit(self: *Channels, alloc: Allocator) void {
        for (self.channels.items) |c| {
            alloc.free(c.name);
        }

        self.channels.deinit(alloc);
    }

    pub fn singleFormat(self: Channels) bool {
        if (0 == self.channels.items.len) {
            return true;
        }

        const format = self.channels.items[0].format;

        for (self.channels.items[1..]) |c| {
            if (format != c.format) {
                return false;
            }
        }

        return true;
    }

    pub fn bytesPerPixel(self: Channels) u32 {
        var size: u32 = 0;
        for (self.channels.items) |c| {
            size += c.format.byteSize();
        }

        return size;
    }

    pub fn read(self: *Channels, alloc: Allocator, stream: ReadStream) !void {
        var buf = std.ArrayListUnmanaged(u8){};

        while (true) {
            var channel: exr.Channel = undefined;

            buf.shrinkRetainingCapacity(0);
            try stream.streamUntilDelimiter(buf.writer(alloc), '\x00', null);
            channel.name = try buf.toOwnedSlice(alloc);

            if (0 == channel.name.len) {
                break;
            }

            _ = try stream.read(std.mem.asBytes(&channel.format));

            // pLinear
            try stream.seekBy(1);

            // reserved
            try stream.seekBy(3);

            // xSampling ySampling
            try stream.seekBy(4 + 4);

            try self.channels.append(alloc, channel);
        }
    }
};
