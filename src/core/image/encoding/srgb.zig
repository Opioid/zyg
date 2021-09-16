const Float4 = @import("../../image/image.zig").Float4;
const base = @import("base");
const Threads = base.thread.Pool;
const ThreadContext = base.thread.Pool.Context;
const encoding = base.encoding;
const spectrum = base.spectrum;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Srgb = struct {
    buffer: []u8 = &.{},

    alpha: bool = undefined,

    image: *const Float4 = undefined,

    pub fn deinit(self: *Srgb, alloc: *Allocator) void {
        alloc.free(self.buffer);
    }

    pub fn resize(self: *Srgb, alloc: *Allocator, num_pixels: u32) !void {
        const num_channels: u32 = if (self.alpha) 4 else 3;
        const num_bytes = num_pixels * num_channels;

        if (num_bytes > self.buffer.len) {
            alloc.free(self.buffer);

            self.buffer = try alloc.alloc(u8, num_bytes);
        }
    }

    pub fn toSrgb(self: *Srgb, image: *const Float4, threads: *Threads) void {
        self.image = image;

        threads.runRange(self, toSrgbRange, 0, @intCast(u32, image.description.numPixels()));
    }

    fn toSrgbRange(context: ThreadContext, id: u32, begin: u32, end: u32) void {
        _ = id;

        const self = @intToPtr(*Srgb, context);

        if (self.alpha) {
            for (self.image.pixels[begin..end]) |p, i| {
                const j = begin + i;
                self.buffer[j * 4 + 0] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[0]));
                self.buffer[j * 4 + 1] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[1]));
                self.buffer[j * 4 + 2] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[2]));
                self.buffer[j * 4 + 3] = encoding.floatToUnorm(std.math.min(p.v[3], 1.0));
            }
        } else {
            for (self.image.pixels[begin..end]) |p, i| {
                const j = begin + i;
                self.buffer[j * 3 + 0] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[0]));
                self.buffer[j * 3 + 1] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[1]));
                self.buffer[j * 3 + 2] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[2]));
            }
        }
    }
};
