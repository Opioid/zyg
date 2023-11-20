const aov = @import("aov_value.zig");

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Pack4f = math.Pack4f;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;

pub const Buffer = struct {
    slots: u32 = 0,

    buffers: [aov.Value.Num_classes][]Pack4f = .{&.{}} ** aov.Value.Num_classes,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        for (self.buffers) |b| {
            alloc.free(b);
        }
    }

    pub fn resize(self: *Self, alloc: Allocator, len: usize, factory: aov.Factory) !void {
        self.slots = factory.slots;

        for (&self.buffers, 0..) |*b, i| {
            if (factory.activeClass(@enumFromInt(i)) and len > b.len) {
                b.* = try alloc.realloc(b.*, len);
            }
        }
    }

    pub fn clear(self: *Self) void {
        for (&self.buffers, 0..) |*b, i| {
            const class: aov.Value.Class = @enumFromInt(i);
            if (class.activeIn(self.slots)) {
                const default = class.default();
                for (b.*) |*p| {
                    p.v = Vec4f{ default[0], default[1], default[2], 0.0 };
                }
            }
        }
    }

    pub fn resolve(self: *const Self, class: aov.Value.Class, target: [*]Pack4f, begin: u32, end: u32) void {
        if (!class.activeIn(self.slots)) {
            return;
        }

        const pixels = self.buffers[@intFromEnum(class)];

        const encoding = class.encoding();
        if (.Color == encoding or .Normal == encoding) {
            for (pixels[begin..end], 0..) |p, i| {
                const color = Vec4f{ p.v[0], p.v[1], p.v[2], 0.0 } / @as(Vec4f, @splat(p.v[3]));
                target[i + begin].v = Vec4f{ color[0], color[1], color[2], 1.0 };
            }
        } else {
            for (pixels[begin..end], 0..) |p, i| {
                target[i + begin].v = Vec4f{ p.v[0], 0.0, 0.0, 1.0 };
            }
        }
    }

    pub fn addPixel(self: *Self, id: u32, slot: u32, value: Vec4f, weight: f32) void {
        const wc = @as(Vec4f, @splat(weight)) * value;

        const pixels = self.buffers[slot];
        var dest: Vec4f = pixels[id].v;
        dest += Vec4f{ wc[0], wc[1], wc[2], weight };
        pixels[id].v = dest;
    }

    pub fn addPixelAtomic(self: *Self, id: u32, slot: u32, value: Vec4f, weight: f32) void {
        const pixels = self.buffers[slot];
        var dest = &pixels[id];

        _ = @atomicRmw(f32, &dest.v[0], .Add, weight * value[0], .Monotonic);
        _ = @atomicRmw(f32, &dest.v[1], .Add, weight * value[1], .Monotonic);
        _ = @atomicRmw(f32, &dest.v[2], .Add, weight * value[2], .Monotonic);
        _ = @atomicRmw(f32, &dest.v[3], .Add, weight, .Monotonic);
    }

    pub fn lessPixel(self: *Self, id: usize, slot: u32, value: f32) void {
        const pixels = self.buffers[slot];
        var dest = &pixels[id];

        if (value < dest.v[0]) {
            dest.v[0] = value;
        }
    }

    pub fn overwritePixel(self: *Self, id: u32, slot: u32, value: f32, weight: f32) void {
        const pixels = self.buffers[slot];
        var dest = &pixels[id];

        if (weight > dest.v[3]) {
            dest.v[0] = value;
            dest.v[3] = weight;
        }
    }
};
