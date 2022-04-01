const Base = @import("base.zig").Base;
const aov = @import("aov/value.zig");

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Pack4f = math.Pack4f;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;

pub const Transparent = struct {
    base: Base,

    pixel_weights: []f32 = &.{},

    pixels: []Pack4f = &.{},

    pub fn init(clamp_max: f32) Transparent {
        return .{ .base = .{ .max = clamp_max } };
    }

    pub fn deinit(self: Transparent, alloc: Allocator) void {
        alloc.free(self.pixels);
        alloc.free(self.pixel_weights);
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
        self.pixels[i].addAssign4(Pack4f.init4(wc[0], wc[1], wc[2], wc[3]));
    }

    pub fn addPixelAtomic(self: *Transparent, pixel: Vec2i, color: Vec4f, weight: f32) void {
        const d = self.base.dimensions;
        const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);

        _ = @atomicRmw(f32, &self.pixel_weights[i], .Add, weight, .Monotonic);

        var value = &self.pixels[i];

        _ = @atomicRmw(f32, &value.v[0], .Add, weight * color[0], .Monotonic);
        _ = @atomicRmw(f32, &value.v[1], .Add, weight * color[1], .Monotonic);
        _ = @atomicRmw(f32, &value.v[2], .Add, weight * color[2], .Monotonic);
        _ = @atomicRmw(f32, &value.v[3], .Add, weight * color[3], .Monotonic);
    }

    pub fn splatPixelAtomic(self: *Transparent, pixel: Vec2i, color: Vec4f, weight: f32) void {
        const d = self.base.dimensions;
        const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);

        var value = &self.pixels[i];

        _ = @atomicRmw(f32, &value.v[0], .Add, weight * color[0], .Monotonic);
        _ = @atomicRmw(f32, &value.v[1], .Add, weight * color[1], .Monotonic);
        _ = @atomicRmw(f32, &value.v[2], .Add, weight * color[2], .Monotonic);
        _ = @atomicRmw(f32, &value.v[3], .Add, weight * color[3], .Monotonic);
    }

    pub fn resolve(self: Transparent, target: [*]Pack4f, begin: u32, end: u32) void {
        for (self.pixels[begin..end]) |p, i| {
            const j = i + begin;
            const weight = self.pixel_weights[j];
            const color = Vec4f{ p.v[0], p.v[1], p.v[2], p.v[3] } / @splat(4, weight);

            target[j] = Pack4f.init4(color[0], color[1], color[2], color[3]);
        }
    }

    pub fn resolveTonemap(self: Transparent, target: [*]Pack4f, begin: u32, end: u32) void {
        for (self.pixels[begin..end]) |p, i| {
            const j = i + begin;
            const weight = self.pixel_weights[j];
            const color = Vec4f{ p.v[0], p.v[1], p.v[2], p.v[3] } / @splat(4, weight);
            const tm = self.base.tonemapper.tonemap(color);
            target[j] = Pack4f.init4(tm[0], tm[1], tm[2], @maximum(color[3], 0.0));
        }
    }

    pub fn resolveAccumulateTonemap(self: Transparent, target: [*]Pack4f, begin: u32, end: u32) void {
        for (self.pixels[begin..end]) |p, i| {
            const j = i + begin;
            const weight = self.pixel_weights[j];
            const color = Vec4f{ p.v[0], p.v[1], p.v[2], p.v[3] } / @splat(4, weight);
            const old = target[j];
            const combined = color + Vec4f{ old.v[0], old.v[1], old.v[2], old.v[3] };
            const tm = self.base.tonemapper.tonemap(combined);
            target[j] = Pack4f.init4(tm[0], tm[1], tm[2], @maximum(combined[3], 0.0));
        }
    }
};
