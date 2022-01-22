const Base = @import("base.zig").Base;
const Float4 = @import("../../image/image.zig").Float4;

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Pack4f = math.Pack4f;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;

pub const Opaque = struct {
    base: Base,

    // weight_sum is saved in pixel.w
    pixels: []Pack4f = &.{},

    pub fn init(clamp_max: f32) Opaque {
        return .{ .base = .{ .max = clamp_max } };
    }

    pub fn deinit(self: *Opaque, alloc: Allocator) void {
        alloc.free(self.pixels);
        self.base.deinit(alloc);
    }

    pub fn resize(self: *Opaque, alloc: Allocator, dimensions: Vec2i) !void {
        try self.base.resize(alloc, dimensions);

        const len = @intCast(usize, dimensions[0] * dimensions[1]);

        if (len > self.pixels.len) {
            self.pixels = try alloc.realloc(self.pixels, len);
        }
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

    pub fn mean(self: Opaque, pixel: Vec2i) Vec4f {
        const d = self.base.dimensions;

        const value = self.pixels[@intCast(usize, d[0] * pixel[1] + pixel[0])];
        const div = if (0.0 == value.v[3]) 1.0 else value.v[3];
        return Vec4f{ value.v[0], value.v[1], value.v[2], 1.0 } / @splat(4, div);
    }

    pub fn addPixel(self: *Opaque, pixel: Vec2i, color: Vec4f, weight: f32) Base.Result {
        const d = self.base.dimensions;

        var value = &self.pixels[@intCast(usize, d[0] * pixel[1] + pixel[0])];
        const wc = @splat(4, weight) * color;

        value.addAssign4(Pack4f.init4(wc[0], wc[1], wc[2], weight));

        const div = if (0.0 == value.v[3]) 1.0 else value.v[3];
        return .{ .last = wc, .mean = Vec4f{ value.v[0], value.v[1], value.v[2], 1.0 } / @splat(4, div) };
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

    pub fn resolve(self: Opaque, target: *Float4, begin: u32, end: u32) void {
        for (self.pixels[begin..end]) |p, i| {
            const color = Vec4f{ p.v[0], p.v[1], p.v[2], 0.0 } / @splat(4, p.v[3]);

            target.pixels[i + begin] = Pack4f.init4(color[0], color[1], color[2], 1.0);
        }
    }

    pub fn resolveAccumlate(self: Opaque, target: *Float4, begin: u32, end: u32) void {
        for (self.pixels[begin..end]) |p, i| {
            const color = Vec4f{ p.v[0], p.v[1], p.v[2], 0.0 } / @splat(4, p.v[3]);

            const j = i + begin;
            const old = target.pixels[j];
            target.pixels[j] = Pack4f.init4(old.v[0] + color[0], old.v[1] + color[1], old.v[2] + color[2], 1.0);
        }
    }

    pub fn copyWeights(self: Opaque, weights: []f32) void {
        for (self.pixels) |p, i| {
            weights[i] = p.v[3];
        }
    }
};
