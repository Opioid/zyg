const Float4 = @import("../../image/image.zig").Float4;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;
const encoding = base.encoding;
const spectrum = base.spectrum;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Srgb = struct {
    buffer: []u8 = &.{},

    error_diffusion: bool,
    alpha: bool,

    image: Float4 = undefined,

    pub fn deinit(self: *Srgb, alloc: Allocator) void {
        alloc.free(self.buffer);
    }

    pub fn resize(self: *Srgb, alloc: Allocator, num_pixels: u32) !void {
        const num_channels: u32 = if (self.alpha) 4 else 3;
        const num_bytes = num_pixels * num_channels;

        if (num_bytes > self.buffer.len) {
            alloc.free(self.buffer);

            self.buffer = try alloc.alloc(u8, num_bytes);
        }
    }

    pub fn toSrgb(self: *Srgb, image: Float4, threads: *Threads) void {
        self.image = image;

        _ = threads.runRange(self, toSrgbRange, 0, @intCast(u32, image.description.dimensions.v[1]));
    }

    fn toSrgbRange(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;

        const self = @intToPtr(*Srgb, context);

        toSrgbBuffer(self.image, self.buffer, self.error_diffusion, self.alpha, begin, end);
    }

    pub fn toSrgbBuffer(image: anytype, buffer: []u8, error_diffusion: bool, alpha: bool, begin: u32, end: u32) void {
        const d = image.description.dimensions;
        const width = @intCast(u32, d.v[0]);

        var y = begin;
        var i = begin * width;

        if (alpha) {
            if (error_diffusion) {
                while (y < end) : (y += 1) {
                    var err = @splat(4, goldenRatio(y) - 0.5);

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
                while (y < end) : (y += 1) {
                    var x: u32 = 0;
                    while (x < width) : (x += 1) {
                        const p = image.pixels[i];

                        buffer[i * 4 + 0] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[0]));
                        buffer[i * 4 + 1] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[1]));
                        buffer[i * 4 + 2] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[2]));
                        buffer[i * 4 + 3] = encoding.floatToUnorm(std.math.min(p.v[3], 1.0));

                        i += 1;
                    }
                }
            }
        } else {
            if (error_diffusion) {
                while (y < end) : (y += 1) {
                    var err = @splat(4, goldenRatio(y) - 0.5);

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
                while (y < end) : (y += 1) {
                    var x: u32 = 0;
                    while (x < width) : (x += 1) {
                        const p = image.pixels[i];

                        buffer[i * 3 + 0] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[0]));
                        buffer[i * 3 + 1] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[1]));
                        buffer[i * 3 + 2] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(p.v[2]));

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
