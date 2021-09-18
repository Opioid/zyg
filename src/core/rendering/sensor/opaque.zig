const Base = @import("base.zig").Base;
const Float4 = @import("../../image/image.zig").Float4;
const math = @import("base").math;
const Vec2i = math.Vec2i;
const Pack4f = math.Pack4f;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;

pub const Opaque = struct {
    base: Base = .{},

    // weight_sum is saved in pixel.w
    pixels: []Pack4f = &.{},

    pub fn deinit(self: *Opaque, alloc: *Allocator) void {
        alloc.free(self.pixels);
    }

    pub fn resize(self: *Opaque, alloc: *Allocator, dimensions: Vec2i) !void {
        self.base.dimensions = dimensions;

        const len = @intCast(usize, dimensions.v[0] * dimensions.v[1]);

        if (len > self.pixels.len) {
            self.pixels = try alloc.realloc(self.pixels, len);
        }
    }

    pub fn clear(self: *Opaque, weight: f32) void {
        for (self.pixels) |*p| {
            p.* = Pack4f.init4(0.0, 0.0, 0.0, weight);
        }
    }

    pub fn addPixel(self: *Opaque, pixel: Vec2i, color: Vec4f, weight: f32) void {
        const d = self.base.dimensions;

        var value = &self.pixels[@intCast(usize, d.v[0] * pixel.v[1] + pixel.v[0])];
        const wc = @splat(4, weight) * color;
        value.addAssign4(Pack4f.init4(wc[0], wc[1], wc[2], weight));
    }

    pub fn addPixelAtomic(self: *Opaque, pixel: Vec2i, color: Vec4f, weight: f32) void {
        const d = self.base.dimensions;

        var value = &self.pixels[@intCast(usize, d.v[0] * pixel.v[1] + pixel.v[0])];

        _ = @atomicRmw(f32, &value.v[0], .Add, weight * color[0], .Monotonic);
        _ = @atomicRmw(f32, &value.v[1], .Add, weight * color[1], .Monotonic);
        _ = @atomicRmw(f32, &value.v[2], .Add, weight * color[2], .Monotonic);
        _ = @atomicRmw(f32, &value.v[3], .Add, weight, .Monotonic);
    }

    pub fn resolve(self: Opaque, target: *Float4) void {
        for (self.pixels) |p, i| {
            const color = Vec4f{ p.v[0], p.v[1], p.v[2], 0.0 } / @splat(4, p.v[3]);

            target.set1D(@intCast(i32, i), Pack4f.init4(color[0], color[1], color[2], 1.0));
        }
    }
};
