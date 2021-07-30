const Float4 = @import("../../image/image.zig").Float4;

const Allocator = @import("std").mem.Allocator;

const std = @import("std");

pub const Srgb = struct {
    buffer: []u8 = &.{},

    alpha: bool = undefined,

    pub fn deinit(self: *Srgb, alloc: *Allocator) void {
        alloc.free(self.buffer);
    }

    pub fn resize(self: *Srgb, alloc: *Allocator, num_pixels: u32) !void {
        const num_channeles: u32 = if (self.alpha) 4 else 3;
        const num_bytes = num_pixels * num_channeles;

        if (num_bytes > self.buffer.len) {
            alloc.free(self.buffer);

            self.buffer = try alloc.alloc(u8, num_bytes);
        }
    }

    pub fn toSrgb(self: *Srgb, image: Float4) void {
        if (self.alpha) {
            for (image.pixels) |p, i| {
                self.buffer[i * 4 + 0] = @floatToInt(u8, 255.0 * std.math.min(p.v[0], 1.0));
                self.buffer[i * 4 + 1] = @floatToInt(u8, 255.0 * std.math.min(p.v[1], 1.0));
                self.buffer[i * 4 + 2] = @floatToInt(u8, 255.0 * std.math.min(p.v[2], 1.0));
                self.buffer[i * 4 + 3] = @floatToInt(u8, 255.0 * std.math.min(p.v[3], 1.0));
            }
        } else {
            for (image.pixels) |p, i| {
                self.buffer[i * 3 + 0] = @floatToInt(u8, 255.0 * std.math.min(p.v[0], 1.0));
                self.buffer[i * 3 + 1] = @floatToInt(u8, 255.0 * std.math.min(p.v[1], 1.0));
                self.buffer[i * 3 + 2] = @floatToInt(u8, 255.0 * std.math.min(p.v[2], 1.0));
            }
        }
    }
};
