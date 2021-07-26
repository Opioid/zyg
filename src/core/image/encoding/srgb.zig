const Float4 = @import("../../image/image.zig").Float4;

const Allocator = @import("std").mem.Allocator;

const std = @import("std");

pub const Srgb = struct {
    buffer: []u8 = &.{},

    pub fn deinit(self: *Srgb, alloc: *Allocator) void {
        alloc.free(self.buffer);
    }

    pub fn resize(self: *Srgb, alloc: *Allocator, num_pixels: u32) !void {
        const num_bytes = num_pixels * 3;

        if (num_bytes > self.buffer.len) {
            alloc.free(self.buffer);

            self.buffer = try alloc.alloc(u8, num_bytes);
        }
    }

    pub fn toSrgb(self: *Srgb, image: Float4) void {
        for (image.pixels) |p, i| {
            self.buffer[i * 3 + 0] = @floatToInt(u8, 255.0 * p.v[0]);
            self.buffer[i * 3 + 1] = @floatToInt(u8, 255.0 * p.v[1]);
            self.buffer[i * 3 + 2] = @floatToInt(u8, 255.0 * p.v[2]);
        }
    }
};
