pub const encoding = @import("encoding/encoding.zig");
const math = @import("base").math;
const Vec2b = math.Vec2b;
const Vec2f = math.Vec2f;
const Vec3b = math.Vec3b;
const Vec3h = math.Vec3h;
const Pack3f = math.Vec3f;
const Pack4f = math.Pack4f;
const ti = @import("typed_image.zig");
pub const Description = ti.Description;
pub const Byte1 = ti.TypedImage(u8);
pub const Byte2 = ti.TypedImage(Vec2b);
pub const Byte3 = ti.TypedImage(Vec3b);
pub const Half3 = ti.TypedImage(Vec3h);
pub const Float1 = ti.TypedImage(f32);
pub const Float2 = ti.TypedImage(Vec2f);
pub const Float3 = ti.TypedImage(Pack3f);
pub const Float4 = ti.TypedImage(Pack4f);

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Swizzle = enum { X, W, XY, XYZ };

pub const Type = enum {
    Byte1,
    Byte2,
    Byte3,
    Half3,
    Float1,
    Float2,
    Float3,
    Float4,
};

pub const Image = union(enum) {
    Byte1: Byte1,
    Byte2: Byte2,
    Byte3: Byte3,
    Half3: Half3,
    Float1: Float1,
    Float2: Float2,
    Float3: Float3,
    Float4: Float4,

    pub fn deinit(self: *Image, alloc: *Allocator) void {
        switch (self.*) {
            .Byte1 => |*i| i.deinit(alloc),
            .Byte2 => |*i| i.deinit(alloc),
            .Byte3 => |*i| i.deinit(alloc),
            .Half3 => |*i| i.deinit(alloc),
            .Float1 => |*i| i.deinit(alloc),
            .Float2 => |*i| i.deinit(alloc),
            .Float3 => |*i| i.deinit(alloc),
            .Float4 => |*i| i.deinit(alloc),
        }
    }

    pub fn description(self: Image) Description {
        return switch (self) {
            .Byte1 => |i| i.description,
            .Byte2 => |i| i.description,
            .Byte3 => |i| i.description,
            .Half3 => |i| i.description,
            .Float1 => |i| i.description,
            .Float2 => |i| i.description,
            .Float3 => |i| i.description,
            .Float4 => |i| i.description,
        };
    }
};
