const Srgb = @import("../srgb.zig").Srgb;
const img = @import("../../image.zig");
const Encoding = @import("../../image_writer.zig").Writer.Encoding;
const Float3 = img.Float3;
const Float4 = img.Float4;

const base = @import("base");
const enc = base.encoding;
const spectrum = base.spectrum;
const math = base.math;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const c = @cImport({
    @cInclude("miniz/miniz.h");
});

pub const Writer = struct {
    srgb: Srgb,

    pub fn init(error_diffusion: bool) Writer {
        return .{ .srgb = .{ .error_diffusion = error_diffusion } };
    }

    pub fn deinit(self: *Writer, alloc: Allocator) void {
        self.srgb.deinit(alloc);
    }

    pub fn write(
        self: *Writer,
        alloc: Allocator,
        writer: anytype,
        image: Float4,
        crop: Vec4i,
        encoding: Encoding,
        threads: *Threads,
    ) !void {
        const d = image.description.dimensions;

        const num_channels = try self.srgb.toSrgb(alloc, image, crop, encoding, threads);

        var buffer_len: usize = 0;
        const png = c.tdefl_write_image_to_png_file_in_memory(
            @as(*const anyopaque, @ptrCast(self.srgb.buffer.ptr)),
            d[0],
            d[1],
            @as(c_int, @intCast(num_channels)),
            &buffer_len,
        );

        try writer.writeAll(@as([*]const u8, @ptrCast(png))[0..buffer_len]);

        c.mz_free(png);
    }

    pub fn writeFloat3Scaled(alloc: Allocator, image: Float3, factor: f32) !void {
        const d = image.description.dimensions;

        const num_pixels = @as(u32, @intCast(d[0] * d[1]));

        const buffer = try alloc.alloc(u8, 3 * num_pixels);
        defer alloc.free(buffer);

        for (image.pixels, 0..) |p, i| {
            const srgb = @as(Vec4f, @splat(factor)) * spectrum.AP1tosRGB(math.vec3fTo4f(p));

            buffer[i * 3 + 0] = enc.floatToUnorm(spectrum.linearToGamma_sRGB(srgb[0]));
            buffer[i * 3 + 1] = enc.floatToUnorm(spectrum.linearToGamma_sRGB(srgb[1]));
            buffer[i * 3 + 2] = enc.floatToUnorm(spectrum.linearToGamma_sRGB(srgb[2]));
        }

        var buffer_len: usize = 0;
        const png = c.tdefl_write_image_to_png_file_in_memory(
            @as(*const anyopaque, @ptrCast(buffer.ptr)),
            d[0],
            d[1],
            3,
            &buffer_len,
        );

        var file = try std.fs.cwd().createFile("temp_image.png", .{});
        defer file.close();

        try file.writer().writeAll(@as([*]const u8, @ptrCast(png))[0..buffer_len]);

        c.mz_free(png);
    }

    pub fn writeFloat3Normal(alloc: Allocator, image: Float3) !void {
        const d = image.description.dimensions;

        const num_pixels = @as(u32, @intCast(d[0] * d[1]));

        const buffer = try alloc.alloc(u8, 3 * num_pixels);
        defer alloc.free(buffer);

        for (image.pixels, 0..) |p, i| {
            buffer[i * 3 + 0] = enc.floatToUnorm(math.saturate(0.5 * (p.v[0] + 1.0)));
            buffer[i * 3 + 1] = enc.floatToUnorm(math.saturate(0.5 * (p.v[1] + 1.0)));
            buffer[i * 3 + 2] = enc.floatToUnorm(math.saturate(0.5 * (p.v[2] + 1.0)));
        }

        var buffer_len: usize = 0;
        const png = c.tdefl_write_image_to_png_file_in_memory(
            @as(*const anyopaque, @ptrCast(buffer.ptr)),
            d[0],
            d[1],
            3,
            &buffer_len,
        );

        var file = try std.fs.cwd().createFile("temp_image.png", .{});
        defer file.close();

        try file.writer().writeAll(@as([*]const u8, @ptrCast(png))[0..buffer_len]);

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
        const num_pixels = @as(u32, @intCast(width * height));
        const buffer = try alloc.alloc(u8, 3 * num_pixels);
        defer alloc.free(buffer);

        const range = max - min;

        for (data, 0..) |p, i| {
            const turbo = spectrum.turbo((p - min) / range);

            buffer[i * 3 + 0] = turbo[0];
            buffer[i * 3 + 1] = turbo[1];
            buffer[i * 3 + 2] = turbo[2];
        }

        var buffer_len: usize = 0;
        const png = c.tdefl_write_image_to_png_file_in_memory(
            @as(*const anyopaque, @ptrCast(buffer.ptr)),
            width,
            height,
            3,
            &buffer_len,
        );

        var file = try std.fs.cwd().createFile(name, .{});
        defer file.close();

        try file.writer().writeAll(@as([*]const u8, @ptrCast(png))[0..buffer_len]);

        c.mz_free(png);
    }
};
