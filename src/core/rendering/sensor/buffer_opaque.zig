const Tonemapper = @import("tonemapper.zig").Tonemapper;

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Pack4f = math.Pack4f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Opaque = struct {
    // weight_sum is saved in pixel.w
    pixels: []Pack4f = &.{},

    pub fn deinit(self: *Opaque, alloc: Allocator) void {
        alloc.free(self.pixels);
    }

    pub fn resize(self: *Opaque, alloc: Allocator, len: usize) !void {
        if (len > self.pixels.len) {
            self.pixels = try alloc.realloc(self.pixels, len);
        }
    }

    pub fn clear(self: *Opaque, weight: f32) void {
        for (self.pixels) |*p| {
            p.v = Vec4f{ 0.0, 0.0, 0.0, weight };
        }
    }

    pub fn fixZeroWeights(self: *Opaque) void {
        for (self.pixels) |*p| {
            if (p.v[3] <= 0.0) {
                p.v[3] = 1.0;
            }
        }
    }

    pub fn addPixel(self: *Opaque, i: u32, color: Vec4f, weight: f32) void {
        const wc = @as(Vec4f, @splat(weight)) * color;
        var value: Vec4f = self.pixels[i].v;
        value += Vec4f{ wc[0], wc[1], wc[2], weight };

        self.pixels[i].v = value;
    }

    pub fn addPixelAtomic(self: *Opaque, i: u32, color: Vec4f, weight: f32) void {
        const wc = @as(Vec4f, @splat(weight)) * color;

        var value = &self.pixels[i];
        _ = @atomicRmw(f32, &value.v[0], .Add, wc[0], .monotonic);
        _ = @atomicRmw(f32, &value.v[1], .Add, wc[1], .monotonic);
        _ = @atomicRmw(f32, &value.v[2], .Add, wc[2], .monotonic);
        _ = @atomicRmw(f32, &value.v[3], .Add, weight, .monotonic);
    }

    pub fn splatPixelAtomic(self: *Opaque, i: u32, color: Vec4f, weight: f32) void {
        const wc = @as(Vec4f, @splat(weight)) * color;

        var value = &self.pixels[i];
        _ = @atomicRmw(f32, &value.v[0], .Add, wc[0], .monotonic);
        _ = @atomicRmw(f32, &value.v[1], .Add, wc[1], .monotonic);
        _ = @atomicRmw(f32, &value.v[2], .Add, wc[2], .monotonic);
    }

    pub fn resolve(self: *const Opaque, target: [*]Pack4f, begin: u32, end: u32) void {
        for (self.pixels[begin..end], 0..) |p, i| {
            const color = @abs(Vec4f{ p.v[0], p.v[1], p.v[2], 0.0 } / @as(Vec4f, @splat(p.v[3])));
            target[i + begin].v = Vec4f{ color[0], color[1], color[2], 1.0 };
        }
    }

    pub fn resolveTonemap(self: *const Opaque, tonemapper: Tonemapper, target: [*]Pack4f, begin: u32, end: u32) void {
        for (self.pixels[begin..end], 0..) |p, i| {
            const color = @abs(Vec4f{ p.v[0], p.v[1], p.v[2], 0.0 } / @as(Vec4f, @splat(p.v[3])));
            const tm = tonemapper.tonemap(color);
            target[i + begin].v = Vec4f{ tm[0], tm[1], tm[2], 1.0 };
        }
    }

    pub fn resolveAccumulateTonemap(self: *const Opaque, tonemapper: Tonemapper, target: [*]Pack4f, begin: u32, end: u32) void {
        for (self.pixels[begin..end], 0..) |p, i| {
            const color = Vec4f{ p.v[0], p.v[1], p.v[2], 0.0 } / @as(Vec4f, @splat(p.v[3]));
            const j = i + begin;
            const old = target[j];
            const combined = @abs(color + Vec4f{ old.v[0], old.v[1], old.v[2], old.v[3] });
            const tm = tonemapper.tonemap(combined);
            target[j].v = Vec4f{ tm[0], tm[1], tm[2], 1.0 };
        }
    }

    pub fn copyWeights(self: *const Opaque, weights: []f32) void {
        for (self.pixels, 0..) |p, i| {
            weights[i] = p.v[3];
        }
    }
};
