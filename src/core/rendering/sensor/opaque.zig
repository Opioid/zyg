const Base = @import("base.zig").Base;

const Float4 = @import("../../image/image.zig").Float4;

usingnamespace @import("base").math;

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

        const len = dimensions.v[0] * dimensions.v[1];

        if (len > self.pixels.len) {
            self.pixels = try alloc.realloc(self.pixels, @intCast(usize, len));
        }
    }

    pub fn clear(self: *Opaque, weight: f32) void {
        for (self.pixels) |*p| {
            p.* = Vec4f.init4(0.0, 0.0, 0.0, weight);
        }
    }

    pub fn addPixel(self: *Opaque, pixel: Vec2i, color: Vec4f, weight: f32) void {
        const d = self.base.dimensions;

        var value = &self.pixels[@intCast(usize, d.v[0] * pixel.v[1] + pixel.v[0])];
        value.addAssign4(Vec4f.init3_1(color.mulScalar3(weight), weight));
    }

    pub fn resolve(self: Opaque, target: *Float4) void {
        for (self.pixels) |p, i| {
            const color = p.divScalar3(p.v[3]);

            target.setX(@intCast(i32, i), Vec4f.init3_1(color, 1.0));
        }
    }
};
