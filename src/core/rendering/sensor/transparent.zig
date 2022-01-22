const Base = @import("base.zig").Base;
const Float4 = @import("../../image/image.zig").Float4;

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

    pub fn deinit(self: *Transparent, alloc: Allocator) void {
        alloc.free(self.pixels);
        alloc.free(self.pixel_weights);
        self.base.deinit(alloc);
    }

    pub fn resize(self: *Transparent, alloc: Allocator, dimensions: Vec2i) !void {
        try self.base.resize(alloc, dimensions);

        const len = @intCast(usize, dimensions[0] * dimensions[1]);

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

    pub fn mean(self: Transparent, pixel: Vec2i) Vec4f {
        const d = self.base.dimensions;
        const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);

        const nw = self.pixel_weights[i];
        const nc = self.pixels[i];
        return Vec4f{ nc.v[0], nc.v[1], nc.v[2], 1.0 } / @splat(4, nw);
    }

    pub fn addPixel(self: *Transparent, pixel: Vec2i, color: Vec4f, weight: f32) Base.Result {
        const d = self.base.dimensions;
        const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);

        self.pixel_weights[i] += weight;

        const wc = @splat(4, weight) * color;
        self.pixels[i].addAssign4(Pack4f.init4(wc[0], wc[1], wc[2], wc[3]));

        const nw = self.pixel_weights[i];
        const nc = self.pixels[i];
        return .{ .last = wc, .mean = Vec4f{ nc.v[0], nc.v[1], nc.v[2], 1.0 } / @splat(4, nw) };
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

    pub fn resolve(self: Transparent, target: *Float4, begin: u32, end: u32) void {
        for (self.pixels[begin..end]) |p, i| {
            const j = i + begin;
            const weight = self.pixel_weights[j];
            const color = Vec4f{ p.v[0], p.v[1], p.v[2], p.v[3] } / @splat(4, weight);

            target.pixels[j] = Pack4f.init4(color[0], color[1], color[2], color[3]);
        }
    }

    pub fn resolveAccumlate(self: Transparent, target: *Float4, begin: u32, end: u32) void {
        for (self.pixels[begin..end]) |p, i| {
            const j = i + begin;
            const weight = self.pixel_weights[j];
            const color = Vec4f{ p.v[0], p.v[1], p.v[2], p.v[3] } / @splat(4, weight);

            const old = target.pixels[j];
            target.pixels[j] = Pack4f.init4(
                old.v[0] + color[0],
                old.v[1] + color[1],
                old.v[2] + color[2],
                old.v[3] + color[3],
            );
        }
    }

    pub fn copyWeights(self: Transparent, weights: []f32) void {
        for (self.pixel_weights) |w, i| {
            weights[i] = w;
        }
    }
};
