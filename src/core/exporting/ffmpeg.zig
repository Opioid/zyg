const Srgb = @import("../image/encoding/srgb.zig").Srgb;
const img = @import("../image/image.zig");
const Float4 = img.Float4;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const FFMPEG = struct {
    srgb: Srgb,

    streams: []std.process.Child,

    const Self = @This();

    pub fn init(alloc: Allocator, dimensions: []Vec2i, framerates: []u32, error_diffusion: bool) !Self {
        var streams = try alloc.alloc(std.process.Child, dimensions.len);

        var framerate_buf: [11]u8 = undefined;
        var res_buf: [22]u8 = undefined;
        var name_buf: [15]u8 = undefined;

        for (dimensions, framerates, 0..) |dim, framerate, i| {
            const framerate_str = try std.fmt.bufPrint(&framerate_buf, "{d}", .{framerate});
            const res_str = try std.fmt.bufPrint(&res_buf, "{d}x{d}", .{ dim[0], dim[1] });
            const name_str = try std.fmt.bufPrint(&name_buf, "output_{d:0>2}.webm", .{i});

            var stream = std.process.Child.init(
                &[_][]const u8{
                    "ffmpeg",
                    "-r",
                    framerate_str,
                    "-f",
                    "rawvideo",
                    "-pix_fmt",
                    "rgb24",
                    "-s",
                    res_str,
                    "-i",
                    "-",
                    "-y",
                    "-c:v",
                    "libvpx-vp9",
                    "-crf",
                    "20",
                    "-b:v",
                    "0",
                    name_str,
                },
                alloc,
            );

            stream.stdin_behavior = .Pipe;
            try stream.spawn();

            streams[i] = stream;
        }

        return FFMPEG{ .srgb = .{ .error_diffusion = error_diffusion }, .streams = streams };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        for (self.streams) |*s| {
            _ = s.kill() catch unreachable;
        }

        alloc.free(self.streams);

        self.srgb.deinit(alloc);
    }

    pub fn write(self: *Self, alloc: Allocator, image: Float4, camera: u32, threads: *Threads) !void {
        const d = image.dimensions;

        _ = try self.srgb.toSrgb(alloc, image, .{ 0, 0, d[0], d[1] }, .Color, threads);

        try self.streams[camera].stdin.?.deprecatedWriter().writeAll(self.srgb.buffer);
    }
};
