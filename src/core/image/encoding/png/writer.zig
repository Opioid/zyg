const Srgb = @import("../srgb.zig").Srgb;
const img = @import("../../image.zig");
const Float3 = img.Float3;
const Float4 = img.Float4;
const AovClass = @import("../../../rendering/sensor/aov/value.zig").Value.Class;

const base = @import("base");
const encoding = base.encoding;
const spectrum = base.spectrum;
const math = base.math;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const c = @cImport({
    @cInclude("miniz/miniz.h");
});

pub const Writer = struct {
    srgb: Srgb,

    pub fn init(error_diffusion: bool, alpha: bool) Writer {
        return .{ .srgb = .{ .error_diffusion = error_diffusion, .alpha = alpha } };
    }

    pub fn deinit(self: *Writer, alloc: Allocator) void {
        self.srgb.deinit(alloc);
    }

    pub fn write(
        self: *Writer,
        alloc: Allocator,
        writer: anytype,
        image: Float4,
        aov: ?AovClass,
        threads: *Threads,
    ) !void {
        const d = image.description.dimensions;

        const num_channels = try self.srgb.toSrgb(alloc, image, aov, threads);

        var buffer_len: usize = 0;
        const png = c.tdefl_write_image_to_png_file_in_memory(
            @ptrCast(*const anyopaque, self.srgb.buffer.ptr),
            d.v[0],
            d.v[1],
            @intCast(c_int, num_channels),
            &buffer_len,
        );

        try writer.writeAll(@ptrCast([*]const u8, png)[0..buffer_len]);

        c.mz_free(png);
    }

    pub fn writeFloat3Scaled(alloc: Allocator, image: Float3, factor: f32) !void {
        const d = image.description.dimensions;

        const num_pixels = @intCast(u32, d.v[0] * d.v[1]);

        const buffer = try alloc.alloc(u8, 3 * num_pixels);
        defer alloc.free(buffer);

        for (image.pixels) |p, i| {
            const srgb = @splat(4, factor) * spectrum.AP1tosRGB(math.vec3fTo4f(p));

            buffer[i * 3 + 0] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(srgb[0]));
            buffer[i * 3 + 1] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(srgb[1]));
            buffer[i * 3 + 2] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(srgb[2]));
        }

        var buffer_len: usize = 0;
        const png = c.tdefl_write_image_to_png_file_in_memory(
            @ptrCast(*const anyopaque, buffer.ptr),
            d.v[0],
            d.v[1],
            3,
            &buffer_len,
        );

        var file = try std.fs.cwd().createFile("temp_image.png", .{});
        defer file.close();

        const writer = file.writer();

        try writer.writeAll(@ptrCast([*]const u8, png)[0..buffer_len]);

        c.mz_free(png);
    }

    pub fn writeHeatmap(
        alloc: Allocator,
        width: i32,
        height: i32,
        data: []const f32,
        min: f32,
        max: f32,
        name: []const u8,
    ) !void {
        const num_pixels = @intCast(u32, width * height);
        const buffer = try alloc.alloc(u8, 3 * num_pixels);
        defer alloc.free(buffer);

        const range = max - min;

        for (data) |p, i| {
            const turbo = spectrum.turbo((p - min) / range);

            buffer[i * 3 + 0] = turbo[0];
            buffer[i * 3 + 1] = turbo[1];
            buffer[i * 3 + 2] = turbo[2];
        }

        var buffer_len: usize = 0;
        const png = c.tdefl_write_image_to_png_file_in_memory(
            @ptrCast(*const anyopaque, buffer.ptr),
            width,
            height,
            3,
            &buffer_len,
        );

        var file = try std.fs.cwd().createFile(name, .{});
        defer file.close();

        const writer = file.writer();

        try writer.writeAll(@ptrCast([*]const u8, png)[0..buffer_len]);

        c.mz_free(png);
    }
};
