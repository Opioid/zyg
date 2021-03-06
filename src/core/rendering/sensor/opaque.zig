const Base = @import("base.zig").Base;
const aov = @import("aov/value.zig");

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Pack4f = math.Pack4f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Opaque = struct {
    base: Base = .{},

    // weight_sum is saved in pixel.w
    pixels: []Pack4f = &.{},

    pub fn init(clamp_max: f32) Opaque {
        return .{ .base = .{ .max = clamp_max } };
    }

    pub fn deinit(self: *Opaque, alloc: Allocator) void {
        alloc.free(self.pixels);
        self.base.aov.deinit(alloc);
    }

    pub fn resize(self: *Opaque, alloc: Allocator, dimensions: Vec2i, factory: aov.Factory) !void {
        self.base.dimensions = dimensions;

        const len = @intCast(usize, dimensions[0] * dimensions[1]);

        if (len > self.pixels.len) {
            self.pixels = try alloc.realloc(self.pixels, len);
        }

        try self.base.aov.resize(alloc, len, factory);
    }

    pub fn clear(self: *Opaque, weight: f32) void {
        for (self.pixels) |*p| {
            p.* = Pack4f.init4(0.0, 0.0, 0.0, weight);
        }
    }

    pub fn fixZeroWeights(self: *Opaque) void {
        for (self.pixels) |*p| {
            if (p.v[3] <= 0.0) {
                p.v[3] = 1.0;
            }
        }
    }

    pub fn addPixel(self: *Opaque, pixel: Vec2i, color: Vec4f, weight: f32) void {
        const d = self.base.dimensions;

        var value = &self.pixels[@intCast(usize, d[0] * pixel[1] + pixel[0])];
        const wc = @splat(4, weight) * color;
        value.addAssign4(Pack4f.init4(wc[0], wc[1], wc[2], weight));
    }

    pub fn addPixelAtomic(self: *Opaque, pixel: Vec2i, color: Vec4f, weight: f32) void {
        const d = self.base.dimensions;

        var value = &self.pixels[@intCast(usize, d[0] * pixel[1] + pixel[0])];

        _ = @atomicRmw(f32, &value.v[0], .Add, weight * color[0], .Monotonic);
        _ = @atomicRmw(f32, &value.v[1], .Add, weight * color[1], .Monotonic);
        _ = @atomicRmw(f32, &value.v[2], .Add, weight * color[2], .Monotonic);
        _ = @atomicRmw(f32, &value.v[3], .Add, weight, .Monotonic);
    }

    pub fn splatPixelAtomic(self: *Opaque, pixel: Vec2i, color: Vec4f, weight: f32) void {
        const d = self.base.dimensions;

        var value = &self.pixels[@intCast(usize, d[0] * pixel[1] + pixel[0])];

        _ = @atomicRmw(f32, &value.v[0], .Add, weight * color[0], .Monotonic);
        _ = @atomicRmw(f32, &value.v[1], .Add, weight * color[1], .Monotonic);
        _ = @atomicRmw(f32, &value.v[2], .Add, weight * color[2], .Monotonic);
    }

    pub fn resolve(self: Opaque, target: [*]Pack4f, begin: u32, end: u32) void {
        for (self.pixels[begin..end]) |p, i| {
            const color = Vec4f{ p.v[0], p.v[1], p.v[2], 0.0 } / @splat(4, p.v[3]);

            target[i + begin] = Pack4f.init4(color[0], color[1], color[2], 1.0);
        }
    }

    pub fn resolveTonemap(self: Opaque, target: [*]Pack4f, begin: u32, end: u32) void {
        for (self.pixels[begin..end]) |p, i| {
            const color = Vec4f{ p.v[0], p.v[1], p.v[2], 0.0 } / @splat(4, p.v[3]);
            const tm = self.base.tonemapper.tonemap(color);
            target[i + begin] = Pack4f.init4(tm[0], tm[1], tm[2], 1.0);
        }
    }

    pub fn resolveAccumulateTonemap(self: Opaque, target: [*]Pack4f, begin: u32, end: u32) void {
        for (self.pixels[begin..end]) |p, i| {
            const color = Vec4f{ p.v[0], p.v[1], p.v[2], 0.0 } / @splat(4, p.v[3]);
            const j = i + begin;
            const old = target[j];
            const combined = color + Vec4f{ old.v[0], old.v[1], old.v[2], old.v[3] };
            const tm = self.base.tonemapper.tonemap(combined);
            target[j] = Pack4f.init4(tm[0], tm[1], tm[2], 1.0);
        }
    }
};
