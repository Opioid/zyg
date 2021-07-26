const Srgb = @import("../srgb.zig").Srgb;
const Float4 = @import("../../image.zig").Float4;

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const c = @cImport({
    @cInclude("miniz/miniz.h");
});

pub const Writer = struct {
    srgb: Srgb = Srgb{},

    pub fn deinit(self: *Writer, alloc: *Allocator) void {
        self.srgb.deinit(alloc);
    }

    pub fn write(self: *Writer, alloc: *Allocator, image: Float4) !void {
        const d = image.description.dimensions;

        const num_pixels = @intCast(u32, d.v[0] * d.v[1]);

        try self.srgb.resize(alloc, num_pixels);

        self.srgb.toSrgb(image);

        var buffer_len: usize = 0;
        const png = c.tdefl_write_image_to_png_file_in_memory(
            @ptrCast(*const c_void, self.srgb.buffer.ptr),
            d.v[0],
            d.v[1],
            3,
            &buffer_len,
        );

        var file = try std.fs.cwd().createFile("image.png", .{});
        defer file.close();

        const writer = file.writer();

        try writer.writeAll(@ptrCast([*]const u8, png)[0..buffer_len]);

        c.mz_free(png);
    }
};
