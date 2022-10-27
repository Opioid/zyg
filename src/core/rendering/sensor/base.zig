const Tonemapper = @import("tonemapper.zig").Tonemapper;
const aov = @import("aov/aov_buffer.zig");

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Base = struct {
    dimensions: Vec2i = @splat(2, @as(i32, 0)),

    max: f32 = std.math.f32_max,

    tonemapper: Tonemapper = Tonemapper.init(.Linear, 0.0),

    aov: aov.Buffer = .{},

    pub fn clamp(self: Base, color: Vec4f) Vec4f {
        const mc = math.maxComponent3(color);

        if (mc > self.max) {
            const r = self.max / mc;
            const s = @splat(4, r) * color;
            return .{ s[0], s[1], s[2], color[3] };
        }

        return color;
    }

    pub fn addAov(self: *Base, pixel: Vec2i, slot: u32, value: Vec4f, weight: f32) void {
        self.aov.addPixel(self.dimensions, pixel, slot, value, weight);
    }

    pub fn addAovAtomic(self: *Base, pixel: Vec2i, slot: u32, value: Vec4f, weight: f32) void {
        self.aov.addPixelAtomic(self.dimensions, pixel, slot, value, weight);
    }

    pub fn lessAov(self: *Base, pixel: Vec2i, slot: u32, value: f32) void {
        self.aov.lessPixel(self.dimensions, pixel, slot, value);
    }

    pub fn overwriteAov(self: *Base, pixel: Vec2i, slot: u32, value: f32, weight: f32) void {
        self.aov.overwritePixel(self.dimensions, pixel, slot, value, weight);
    }
};
