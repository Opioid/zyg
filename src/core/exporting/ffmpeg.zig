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

    stream: std.ChildProcess,

    const Self = @This();

    pub fn init(
        alloc: Allocator,
        dimensions: Vec2i,
        framerate: u32,
        error_diffusion: bool,
    ) !Self {
        var framerate_buf: [11]u8 = undefined;
        const framerate_str = try std.fmt.bufPrint(
            &framerate_buf,
            "{d}",
            .{framerate},
        );

        var res_buf: [22]u8 = undefined;
        const res_str = try std.fmt.bufPrint(
            &res_buf,
            "{d}x{d}",
            .{ dimensions[0], dimensions[1] },
        );

        var stream = std.ChildProcess.init(
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
                "output.webm",
            },
            alloc,
        );

        stream.stdin_behavior = .Pipe;
        try stream.spawn();

        return FFMPEG{
            .srgb = .{ .error_diffusion = error_diffusion },
            .stream = stream,
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        _ = self.stream.kill() catch unreachable;

        self.srgb.deinit(alloc);
    }

    pub fn write(self: *Self, alloc: Allocator, image: Float4, threads: *Threads) !void {
        const d = image.description.dimensions;

        _ = try self.srgb.toSrgb(alloc, image, .{ 0, 0, d[0], d[1] }, .Color, threads);

        try self.stream.stdin.?.writer().writeAll(self.srgb.buffer);
    }
};
