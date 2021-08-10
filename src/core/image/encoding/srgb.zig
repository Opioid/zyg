const Float4 = @import("../../image/image.zig").Float4;
usingnamespace @import("base");

const ThreadContext = thread.Pool.Context;

const Allocator = @import("std").mem.Allocator;

const std = @import("std");

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

    pub fn toSrgb(self: *Srgb, image: *const Float4, threads: *thread.Pool) void {
        self.image = image;

        threads.runRange(self, toSrgbRange, 0, @intCast(u32, image.description.numPixels()));
    }

    fn toSrgbRange(context: *ThreadContext, id: u32, begin: u32, end: u32) void {
        _ = id;

        const self = @ptrCast(*Srgb, context);

        if (self.alpha) {
            var i = begin;
            while (i < end) : (i += 1) {
                const p = self.image.pixels[i];

                self.buffer[i * 4 + 0] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[0]));
                self.buffer[i * 4 + 1] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[1]));
                self.buffer[i * 4 + 2] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[2]));
                self.buffer[i * 4 + 3] = encoding.floatToUnorm(std.math.min(p.v[3], 1.0));
            }
        } else {
            var i = begin;
            while (i < end) : (i += 1) {
                const p = self.image.pixels[i];

                self.buffer[i * 3 + 0] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[0]));
                self.buffer[i * 3 + 1] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[1]));
                self.buffer[i * 3 + 2] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[2]));
            }
        }
    }
};
