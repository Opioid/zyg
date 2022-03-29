const aov = @import("value.zig");
const Float4 = @import("../../../image/image.zig").Float4;

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Pack4f = math.Pack4f;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;

pub const Buffer = struct {
    slots: u32 = 0,

    buffers: [aov.Value.Num_classes][]Pack4f = .{ &.{}, &.{}, &.{}, &.{} },

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        for (self.buffers) |b| {
            alloc.free(b);
        }
    }

    pub fn resize(self: *Self, alloc: Allocator, len: usize, factory: aov.Factory) !void {
        self.slots = factory.slots;

        for (self.buffers) |*b, i| {
            if (factory.activeClass(@intToEnum(aov.Value.Class, i)) and len > b.len) {
                b.* = try alloc.realloc(b.*, len);
            }
        }
    }

    pub fn resolve(self: Self, class: aov.Value.Class, target: *Float4, begin: u32, end: u32) void {
        const bit = @as(u32, 1) << @enumToInt(class);
        if (0 == (self.slots & bit)) {
            return;
        }

        const pixels = self.buffers[@enumToInt(class)];

        for (pixels[begin..end]) |p, i| {
            const color = Vec4f{ p.v[0], p.v[1], p.v[2], 0.0 } / @splat(4, p.v[3]);

            target.pixels[i + begin] = Pack4f.init4(color[0], color[1], color[2], 1.0);
        }
    }

    pub fn addPixel(
        self: *Self,
        dimensions: Vec2i,
        pixel: Vec2i,
        slot: u32,
        value: Vec4f,
        weight: f32,
    ) void {
        const d = dimensions;

        const pixels = self.buffers[slot];
        var dest = &pixels[@intCast(usize, d[0] * pixel[1] + pixel[0])];
        const wc = @splat(4, weight) * value;
        dest.addAssign4(Pack4f.init4(wc[0], wc[1], wc[2], weight));
    }

    pub fn addPixelAtomic(
        self: *Self,
        dimensions: Vec2i,
        pixel: Vec2i,
        slot: u32,
        value: Vec4f,
        weight: f32,
    ) void {
        const d = dimensions;

        const pixels = self.buffers[slot];
        var dest = &pixels[@intCast(usize, d[0] * pixel[1] + pixel[0])];

        _ = @atomicRmw(f32, &dest.v[0], .Add, weight * value[0], .Monotonic);
        _ = @atomicRmw(f32, &dest.v[1], .Add, weight * value[1], .Monotonic);
        _ = @atomicRmw(f32, &dest.v[2], .Add, weight * value[2], .Monotonic);
        _ = @atomicRmw(f32, &dest.v[3], .Add, weight, .Monotonic);
    }
};
