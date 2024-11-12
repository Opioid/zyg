const Opaque = @import("buffer_opaque.zig").Opaque;
const Transparent = @import("buffer_transparent.zig").Transparent;
const Tonemapper = @import("tonemapper.zig").Tonemapper;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;
const Pack4f = math.Pack4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Buffer = union(Class) {
    pub const Class = enum {
        Opaque,
        Transparent,
    };

    Opaque: Opaque,
    Transparent: Transparent,

    const Self = @This();

    pub fn init(class: Class) Self {
        return switch (class) {
            .Opaque => .{ .Opaque = .{} },
            .Transparent => .{ .Transparent = .{} },
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        switch (self.*) {
            inline else => |*s| s.deinit(alloc),
        }
    }

    pub fn resize(self: *Self, alloc: Allocator, len: usize) !void {
        try switch (self.*) {
            inline else => |*s| s.resize(alloc, len),
        };
    }

    pub fn clear(self: *Self, weight: f32) void {
        switch (self.*) {
            inline else => |*s| s.clear(weight),
        }
    }

    pub fn fixZeroWeights(self: *Self) void {
        switch (self.*) {
            inline else => |*s| s.fixZeroWeights(),
        }
    }

    pub fn addPixel(self: *Self, i: u32, color: Vec4f, weight: f32) void {
        switch (self.*) {
            inline else => |*s| s.addPixel(i, color, weight),
        }
    }

    pub fn addPixelAtomic(self: *Self, i: u32, color: Vec4f, weight: f32) void {
        switch (self.*) {
            inline else => |*s| s.addPixelAtomic(i, color, weight),
        }
    }

    pub fn splatPixelAtomic(self: *Self, i: u32, color: Vec4f, weight: f32) void {
        switch (self.*) {
            inline else => |*s| s.splatPixelAtomic(i, color, weight),
        }
    }

    pub fn resolve(self: *const Self, target: [*]Pack4f, begin: u32, end: u32) void {
        switch (self.*) {
            inline else => |*s| s.resolve(target, begin, end),
        }
    }

    pub fn resolveTonemap(self: *const Self, tonemapper: Tonemapper, target: [*]Pack4f, begin: u32, end: u32) void {
        switch (self.*) {
            inline else => |*s| s.resolveTonemap(tonemapper, target, begin, end),
        }
    }

    pub fn resolveAccumulateTonemap(self: *const Self, tonemapper: Tonemapper, target: [*]Pack4f, begin: u32, end: u32) void {
        switch (self.*) {
            inline else => |*s| s.resolveAccumulateTonemap(tonemapper, target, begin, end),
        }
    }

    pub fn alphaTransparency(self: *const Self) bool {
        return switch (self.*) {
            .Transparent => true,
            else => false,
        };
    }
};
