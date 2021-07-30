const Base = @import("base.zig").Base;
const Float4 = @import("../../image/image.zig").Float4;

usingnamespace @import("base").math;

const Allocator = @import("std").mem.Allocator;

pub const Transparent = struct {
    base: Base = .{},

    pixel_weights: []f32 = &.{},

    pixels: []Vec4f = &.{},

    pub fn deinit(self: Transparent, alloc: *Allocator) void {
        alloc.free(self.pixels);
        alloc.free(self.pixel_weights);
    }

    pub fn resize(self: *Transparent, alloc: *Allocator, dimensions: Vec2i) !void {
        self.base.dimensions = dimensions;

        const len = @intCast(usize, dimensions.v[0] * dimensions.v[1]);

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
            p.* = Vec4f.init1(0.0);
        }
    }

    pub fn addPixel(self: *Transparent, pixel: Vec2i, color: Vec4f, weight: f32) void {
        const d = self.base.dimensions;
        const i = @intCast(usize, d.v[0] * pixel.v[1] + pixel.v[0]);

        self.pixel_weights[i] += weight;
        self.pixels[i].addAssign4(color.mulScalar4(weight));
    }

    pub fn resolve(self: Transparent, target: *Float4) void {
        for (self.pixels) |p, i| {
            const weight = self.pixel_weights[i];
            const color = p.divScalar4(weight);

            target.setX(@intCast(i32, i), color);
        }
    }
};
