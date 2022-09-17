const Base = @import("base.zig").Base;
const aov = @import("aov/value.zig");

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Pack4f = math.Pack4f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Transparent = struct {
    base: Base = .{},

    pixel_weights: []f32 = &.{},

    pixels: []Pack4f = &.{},

    pub fn init(clamp_max: f32) Transparent {
        return .{ .base = .{ .max = clamp_max } };
    }

    pub fn deinit(self: *Transparent, alloc: Allocator) void {
        alloc.free(self.pixels);
        alloc.free(self.pixel_weights);
        self.base.aov.deinit(alloc);
    }

    pub fn resize(self: *Transparent, alloc: Allocator, dimensions: Vec2i, factory: aov.Factory) !void {
        self.base.dimensions = dimensions;

        const len = @intCast(usize, dimensions[0] * dimensions[1]);

        if (len > self.pixels.len) {
            self.pixel_weights = try alloc.realloc(self.pixel_weights, len);
            self.pixels = try alloc.realloc(self.pixels, len);
        }

        try self.base.aov.resize(alloc, len, factory);
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

    pub fn addPixel(self: *Transparent, pixel: Vec2i, color: Vec4f, weight: f32) void {
        const d = self.base.dimensions;
        const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);

        self.pixel_weights[i] += weight;

        const wc = @splat(4, weight) * color;
        var value: Vec4f = self.pixels[i].v;
        value += wc;

        self.pixels[i].v = value;
    }

    pub fn addPixelAtomic(self: *Transparent, pixel: Vec2i, color: Vec4f, weight: f32) void {
        const d = self.base.dimensions;
        const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);

        _ = @atomicRmw(f32, &self.pixel_weights[i], .Add, weight, .Monotonic);

        const wc = @splat(4, weight) * color;

        var value = &self.pixels[i];
        _ = @atomicRmw(f32, &value.v[0], .Add, wc[0], .Monotonic);
        _ = @atomicRmw(f32, &value.v[1], .Add, wc[1], .Monotonic);
        _ = @atomicRmw(f32, &value.v[2], .Add, wc[2], .Monotonic);
        _ = @atomicRmw(f32, &value.v[3], .Add, wc[3], .Monotonic);
    }

    pub fn splatPixelAtomic(self: *Transparent, pixel: Vec2i, color: Vec4f, weight: f32) void {
        const d = self.base.dimensions;
        const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);

        const wc = @splat(4, weight) * color;

        var value = &self.pixels[i];
        _ = @atomicRmw(f32, &value.v[0], .Add, wc[0], .Monotonic);
        _ = @atomicRmw(f32, &value.v[1], .Add, wc[1], .Monotonic);
        _ = @atomicRmw(f32, &value.v[2], .Add, wc[2], .Monotonic);
        _ = @atomicRmw(f32, &value.v[3], .Add, wc[3], .Monotonic);
    }

    pub fn resolve(self: Transparent, target: [*]Pack4f, begin: u32, end: u32) void {
        for (self.pixels[begin..end]) |p, i| {
            const j = i + begin;
            const weight = self.pixel_weights[j];
            const color = @as(Vec4f, p.v) / @splat(4, weight);

            target[j].v = color;
        }
    }

    pub fn resolveTonemap(self: Transparent, target: [*]Pack4f, begin: u32, end: u32) void {
        for (self.pixels[begin..end]) |p, i| {
            const j = i + begin;
            const weight = self.pixel_weights[j];
            const color = @as(Vec4f, p.v) / @splat(4, weight);
            const tm = self.base.tonemapper.tonemap(color);
            target[j].v = Vec4f{ tm[0], tm[1], tm[2], std.math.max(color[3], 0.0) };
        }
    }

    pub fn resolveAccumulateTonemap(self: Transparent, target: [*]Pack4f, begin: u32, end: u32) void {
        for (self.pixels[begin..end]) |p, i| {
            const j = i + begin;
            const weight = self.pixel_weights[j];
            const color = @as(Vec4f, p.v) / @splat(4, weight);
            const old = target[j];
            const combined = color + @as(Vec4f, old.v);
            const tm = self.base.tonemapper.tonemap(combined);
            target[j].v = Vec4f{ tm[0], tm[1], tm[2], std.math.max(combined[3], 0.0) };
        }
    }
};
