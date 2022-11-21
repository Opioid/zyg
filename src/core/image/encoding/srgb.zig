const Float4 = @import("../../image/image.zig").Float4;
const Encoding = @import("../../image/image_writer.zig").Writer.Encoding;
const scn = @import("../../scene/constants.zig");

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;
const enc = base.encoding;
const spectrum = base.spectrum;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Srgb = struct {
    buffer: []u8 = &.{},

    error_diffusion: bool,

    image: Float4 = undefined,
    crop: Vec4i = undefined,
    encoding: Encoding = undefined,

    min_depth: f32 = undefined,
    max_depth: f32 = undefined,

    pub fn deinit(self: *Srgb, alloc: Allocator) void {
        alloc.free(self.buffer);
    }

    pub fn toSrgb(self: *Srgb, alloc: Allocator, image: Float4, crop: Vec4i, encoding: Encoding, threads: *Threads) !u32 {
        const d = image.description.dimensions;
        const num_pixels = @intCast(u32, d[0] * d[1]);

        const xy = Vec2i{ crop[0], crop[1] };
        const zw = Vec2i{ crop[2], crop[3] };
        const dim = zw - xy;

        var num_channels: u32 = 3;

        var mind: f32 = std.math.f32_max;
        var maxd: f32 = 0.0;

        switch (encoding) {
            .Color, .Normal, .Id => num_channels = 3,
            .Color_alpha => num_channels = 4,
            .Depth => {
                num_channels = 1;

                var y = crop[1];
                while (y < crop[3]) : (y += 1) {
                    var i = @intCast(u32, y * d[0] + crop[0]);

                    var x = crop[1];
                    while (x < crop[2]) : (x += 1) {
                        const depth = image.pixels[i].v[0];

                        mind = std.math.min(mind, depth);

                        if (depth < scn.Almost_ray_max_t) {
                            maxd = std.math.max(maxd, depth);
                        }

                        i += 1;
                    }
                }
            },
            .Float => num_channels = 1,
        }

        const num_bytes = num_pixels * num_channels;

        if (num_bytes > self.buffer.len) {
            alloc.free(self.buffer);

            self.buffer = try alloc.alloc(u8, num_bytes);
        }

        self.image = image;
        self.crop = crop;
        self.encoding = encoding;
        self.min_depth = mind;
        self.max_depth = maxd;

        if (d[0] != dim[0] or d[1] != dim[1]) {
            std.mem.set(u8, self.buffer[0..num_bytes], 0);
        }

        _ = threads.runRange(self, toSrgbRange, 0, @intCast(u32, dim[1]), 0);

        return num_channels;
    }

    fn toSrgbRange(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;

        const self = @intToPtr(*Srgb, context);

        self.toSrgbBuffer(begin, end);
    }

    fn toSrgbBuffer(self: *Srgb, begin: u32, end: u32) void {
        const d = self.image.description.dimensions;
        const data_width = @intCast(u32, d[0]);

        const crop = self.crop;
        const xy = Vec2i{ crop[0], crop[1] };
        const zw = Vec2i{ crop[2], crop[3] };
        const dim = zw - xy;
        const width = @intCast(u32, dim[0]);
        const x_start = @intCast(u32, crop[0]);
        const y_start = @intCast(u32, crop[1]);

        const y_end = y_start + end;

        var y = y_start + begin;

        const asColor = .Color == self.encoding or .Color_alpha == self.encoding;
        const alpha = .Color_alpha == self.encoding;

        const image = self.image;
        const buffer = self.buffer;

        if (asColor) {
            if (alpha) {
                if (self.error_diffusion) {
                    while (y < y_end) : (y += 1) {
                        var err = @splat(4, goldenRatio(y) - 0.5);

                        var i = y * data_width + x_start;
                        var x: u32 = 0;
                        while (x < width) : (x += 1) {
                            const p = image.pixels[i];

                            const color = Vec4f{
                                spectrum.linearToGamma_sRGB(p.v[0]),
                                spectrum.linearToGamma_sRGB(p.v[1]),
                                spectrum.linearToGamma_sRGB(p.v[2]),
                                std.math.min(p.v[3], 1.0),
                            };

                            const cf = @splat(4, @as(f32, 255.0)) * color;
                            const ci = math.vec4fTo4b(cf + err + @splat(4, @as(f32, 0.5)));

                            err += cf - math.vec4bTo4f(ci);

                            buffer[i * 4 + 0] = ci[0];
                            buffer[i * 4 + 1] = ci[1];
                            buffer[i * 4 + 2] = ci[2];
                            buffer[i * 4 + 3] = ci[3];

                            i += 1;
                        }
                    }
                } else {
                    while (y < y_end) : (y += 1) {
                        var i = y * data_width + x_start;
                        var x: u32 = 0;
                        while (x < width) : (x += 1) {
                            const p = image.pixels[i];

                            buffer[i * 4 + 0] = enc.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[0]));
                            buffer[i * 4 + 1] = enc.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[1]));
                            buffer[i * 4 + 2] = enc.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[2]));
                            buffer[i * 4 + 3] = enc.floatToUnorm(std.math.min(p.v[3], 1.0));

                            i += 1;
                        }
                    }
                }
            } else {
                if (self.error_diffusion) {
                    while (y < y_end) : (y += 1) {
                        var err = @splat(4, goldenRatio(y) - 0.5);

                        var i = y * data_width + x_start;
                        var x: u32 = 0;
                        while (x < width) : (x += 1) {
                            const p = image.pixels[i];

                            const color = Vec4f{
                                spectrum.linearToGamma_sRGB(p.v[0]),
                                spectrum.linearToGamma_sRGB(p.v[1]),
                                spectrum.linearToGamma_sRGB(p.v[2]),
                                0.0,
                            };

                            const cf = @splat(4, @as(f32, 255.0)) * color;
                            const ci = math.vec4fTo3b(cf + err + @splat(4, @as(f32, 0.5)));

                            err += cf - math.vec3bTo4f(ci);

                            buffer[i * 3 + 0] = ci.v[0];
                            buffer[i * 3 + 1] = ci.v[1];
                            buffer[i * 3 + 2] = ci.v[2];

                            i += 1;
                        }
                    }
                } else {
                    while (y < y_end) : (y += 1) {
                        var i = y * data_width + x_start;
                        var x: u32 = 0;
                        while (x < width) : (x += 1) {
                            const p = image.pixels[i];

                            buffer[i * 3 + 0] = enc.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[0]));
                            buffer[i * 3 + 1] = enc.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[1]));
                            buffer[i * 3 + 2] = enc.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[2]));

                            i += 1;
                        }
                    }
                }
            }
        } else {
            if (.Depth == self.encoding) {
                const mind = self.min_depth;
                const range = self.max_depth - mind;

                while (y < y_end) : (y += 1) {
                    var i = y * data_width + x_start;
                    var x: u32 = 0;
                    while (x < width) : (x += 1) {
                        const depth = image.pixels[i].v[0];

                        buffer[i] = enc.floatToUnorm(math.saturate(1.0 - (depth - mind) / range));

                        i += 1;
                    }
                }
            } else if (.Float == self.encoding) {
                while (y < y_end) : (y += 1) {
                    var i = y * data_width + x_start;
                    var x: u32 = 0;
                    while (x < width) : (x += 1) {
                        const f = image.pixels[i].v[0];

                        buffer[i] = enc.floatToUnorm(math.saturate(f));

                        i += 1;
                    }
                }
            } else if (.Id == self.encoding) {
                while (y < y_end) : (y += 1) {
                    var i = y * data_width + x_start;
                    var x: u32 = 0;
                    while (x < width) : (x += 1) {
                        const id = @floatToInt(u32, image.pixels[i].v[0]);
                        const mid = (id *% 9795927) % 16777216;

                        buffer[i * 3 + 0] = @truncate(u8, mid >> 16);
                        buffer[i * 3 + 1] = @truncate(u8, mid >> 8);
                        buffer[i * 3 + 2] = @truncate(u8, mid);

                        i += 1;
                    }
                }
            } else if (.Normal == self.encoding) {
                while (y < y_end) : (y += 1) {
                    var i = y * data_width + x_start;
                    var x: u32 = 0;
                    while (x < width) : (x += 1) {
                        const p = image.pixels[i];

                        buffer[i * 3 + 0] = enc.floatToUnorm(math.saturate(0.5 * (p.v[0] + 1.0)));
                        buffer[i * 3 + 1] = enc.floatToUnorm(math.saturate(0.5 * (p.v[1] + 1.0)));
                        buffer[i * 3 + 2] = enc.floatToUnorm(math.saturate(0.5 * (p.v[2] + 1.0)));

                        i += 1;
                    }
                }
            }
        }
    }

    fn goldenRatio(n: u32) f32 {
        return math.frac(@intToFloat(f32, n) * 0.618033988749894);
    }
};
