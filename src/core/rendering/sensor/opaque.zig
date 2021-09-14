const Base = @import("base.zig").Base;
const Float4 = @import("../../image/image.zig").Float4;
const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;

pub const Opaque = struct {
    base: Base = .{},

    // weight_sum is saved in pixel.w
    pixels: []Vec4f = &.{},

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
            p.* = .{ 0.0, 0.0, 0.0, weight };
        }
    }

    pub fn addPixel(self: *Opaque, pixel: Vec2i, color: Vec4f, weight: f32) void {
        const d = self.base.dimensions;

        var value = &self.pixels[@intCast(usize, d.v[0] * pixel.v[1] + pixel.v[0])];
        const wc = @splat(4, weight) * color;
        value.* += Vec4f{ wc[0], wc[1], wc[2], weight };
    }

    pub fn addPixelAtomic(self: *Opaque, pixel: Vec2i, color: Vec4f, weight: f32) void {
        _ = self;
        _ = pixel;
        _ = color;
        _ = weight;

        // const d = self.base.dimensions;

        // var value = &self.pixels[@intCast(usize, d.v[0] * pixel.v[1] + pixel.v[0])];

        // _ = @atomicRmw(f32, &value[0], .Add, weight * color[0], .Monotonic);
        // _ = @atomicRmw(f32, &value[1], .Add, weight * color[1], .Monotonic);
        // _ = @atomicRmw(f32, &value[2], .Add, weight * color[2], .Monotonic);
        // _ = @atomicRmw(f32, &value[3], .Add, weight, .Monotonic);
    }

    pub fn resolve(self: Opaque, target: *Float4) void {
        for (self.pixels) |p, i| {
            const color = p / @splat(4, p[3]);

            target.setX(@intCast(i32, i), .{ color[0], color[1], color[2], 1.0 });
        }
    }
};
