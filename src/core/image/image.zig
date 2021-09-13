pub const encoding = @import("encoding/encoding.zig");
const math = @import("base").math;
const Vec2b = math.Vec2b;
const Vec3b = math.Vec3b;
const Vec4f = math.Vec4f;
const ti = @import("typed_image.zig");
pub const Description = ti.Description;
pub const Byte1 = ti.Typed_image(u8);
pub const Byte2 = ti.Typed_image(Vec2b);
pub const Byte3 = ti.Typed_image(Vec3b);
pub const Float4 = ti.Typed_image(Vec4f);

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Swizzle = enum { Undefined, W, XY, XYZ };

pub const Image = union(enum) {
    Byte1: Byte1,
    Byte2: Byte2,
    Byte3: Byte3,
    Float4: Float4,

    pub fn deinit(self: *Image, alloc: *Allocator) void {
        switch (self.*) {
            .Byte1 => |*i| i.deinit(alloc),
            .Byte2 => |*i| i.deinit(alloc),
            .Byte3 => |*i| i.deinit(alloc),
            .Float4 => |*i| i.deinit(alloc),
        }
    }

    pub fn description(self: Image) Description {
        return switch (self) {
            .Byte1 => |i| i.description,
            .Byte2 => |i| i.description,
            .Byte3 => |i| i.description,
            .Float4 => |i| i.description,
        };
    }
};
