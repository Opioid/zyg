const Tonemapper = @import("tonemapper.zig").Tonemapper;

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Pack4f = math.Pack4f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Transparent = struct {
    pixel_weights: []f32 = &.{},

    pixels: []Pack4f = &.{},

    pub fn deinit(self: *Transparent, alloc: Allocator) void {
        alloc.free(self.pixels);
        alloc.free(self.pixel_weights);
    }

    pub fn resize(self: *Transparent, alloc: Allocator, len: usize) !void {
        if (len > self.pixels.len) {
            self.pixel_weights = try alloc.realloc(self.pixel_weights, len);
            self.pixels = try alloc.realloc(self.pixels, len);
        }
    }

    pub fn clear(self: *Transparent, weight: f32) void {
        for (self.pixel_weights) |*w| {
            w.* = weight;
        }

        for (self.pixels) |*p| {
            p.* = Pack4f.init1(0.0);
        }
    }

    pub fn fixZeroWeights(self: *Transparent) void {
        for (self.pixel_weights) |*w| {
            if (w.* <= 0.0) {
                w.* = 1.0;
            }
        }
    }

    pub fn addPixel(self: *Transparent, i: usize, color: Vec4f, weight: f32) void {
        self.pixel_weights[i] += weight;

        const wc = @as(Vec4f, @splat(weight)) * color;
        var value: Vec4f = self.pixels[i].v;
        value += wc;

        self.pixels[i].v = value;
    }

    pub fn addPixelAtomic(self: *Transparent, i: usize, color: Vec4f, weight: f32) void {
        _ = @atomicRmw(f32, &self.pixel_weights[i], .Add, weight, .Monotonic);

        const wc = @as(Vec4f, @splat(weight)) * color;

        var value = &self.pixels[i];
        _ = @atomicRmw(f32, &value.v[0], .Add, wc[0], .Monotonic);
        _ = @atomicRmw(f32, &value.v[1], .Add, wc[1], .Monotonic);
        _ = @atomicRmw(f32, &value.v[2], .Add, wc[2], .Monotonic);
        _ = @atomicRmw(f32, &value.v[3], .Add, wc[3], .Monotonic);
    }

    pub fn splatPixelAtomic(self: *Transparent, i: usize, color: Vec4f, weight: f32) void {
        const wc = @as(Vec4f, @splat(weight)) * color;

        var value = &self.pixels[i];
        _ = @atomicRmw(f32, &value.v[0], .Add, wc[0], .Monotonic);
        _ = @atomicRmw(f32, &value.v[1], .Add, wc[1], .Monotonic);
        _ = @atomicRmw(f32, &value.v[2], .Add, wc[2], .Monotonic);
        _ = @atomicRmw(f32, &value.v[3], .Add, wc[3], .Monotonic);
    }

    pub fn resolve(self: *const Transparent, target: [*]Pack4f, begin: u32, end: u32) void {
        for (self.pixels[begin..end], 0..) |p, i| {
            const j = i + begin;
            const weight = self.pixel_weights[j];
            const color = @fabs(@as(Vec4f, p.v) / @as(Vec4f, @splat(weight)));
            target[j].v = color;
        }
    }

    pub fn resolveTonemap(self: *const Transparent, tonemapper: Tonemapper, target: [*]Pack4f, begin: u32, end: u32) void {
        const weights = self.pixel_weights;
        for (self.pixels[begin..end], 0..) |p, i| {
            const j = i + begin;
            const weight = weights[j];
            const color = @fabs(@as(Vec4f, p.v) / @as(Vec4f, @splat(weight)));
            const tm = tonemapper.tonemap(color);
            target[j].v = Vec4f{ tm[0], tm[1], tm[2], color[3] };
        }
    }

    pub fn resolveAccumulateTonemap(self: *const Transparent, tonemapper: Tonemapper, target: [*]Pack4f, begin: u32, end: u32) void {
        const weights = self.pixel_weights;
        for (self.pixels[begin..end], 0..) |p, i| {
            const j = i + begin;
            const weight = weights[j];
            const color = @as(Vec4f, p.v) / @as(Vec4f, @splat(weight));
            const old = target[j];
            const combined = @fabs(color + @as(Vec4f, old.v));
            const tm = tonemapper.tonemap(combined);
            target[j].v = Vec4f{ tm[0], tm[1], tm[2], combined[3] };
        }
    }
};
