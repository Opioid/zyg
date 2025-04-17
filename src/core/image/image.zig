const math = @import("base").math;
const Vec2b = math.Vec2b;
const Vec2f = math.Vec2f;
const Pack3b = math.Pack3b;
const Pack3h = math.Pack3h;
const Pack3f = math.Pack3f;
const Pack4b = math.Pack4b;
const Pack4h = math.Pack4h;
const Pack4f = math.Pack4f;
const ti = @import("typed_image.zig");
pub const Description = ti.Description;
pub const Byte1 = ti.TypedImage(u8);
pub const Byte2 = ti.TypedImage(Vec2b);
pub const Byte3 = ti.TypedImage(Pack3b);
pub const Byte4 = ti.TypedImage(Pack4b);
pub const Half1 = ti.TypedImage(f16);
pub const Half3 = ti.TypedImage(Pack3h);
pub const Half4 = ti.TypedImage(Pack4h);
pub const Float1 = ti.TypedImage(f32);
pub const Float1Sparse = ti.TypedSparseImage(f32);
pub const Float2 = ti.TypedImage(Vec2f);
pub const Float3 = ti.TypedImage(Pack3f);
pub const Float4 = ti.TypedImage(Pack4f);
pub const testing = @import("test_image.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Swizzle = enum {
    X,
    Y,
    Z,
    W,
    XY,
    YX,
    YZ,
    XYZ,
    XYZW,

    pub fn numChannels(self: Swizzle) u32 {
        return switch (self) {
            .X, .Y, .Z, .W => 1,
            .XY, .YX, .YZ => 2,
            .XYZ => 3,
            .XYZW => 4,
        };
    }
};

pub const Image = union(enum) {
    Byte1: Byte1,
    Byte2: Byte2,
    Byte3: Byte3,
    Byte4: Byte4,
    Half1: Half1,
    Half3: Half3,
    Half4: Half4,
    Float1: Float1,
    Float1Sparse: Float1Sparse,
    Float2: Float2,
    Float3: Float3,
    Float4: Float4,

    pub fn deinit(self: *Image, alloc: Allocator) void {
        switch (self.*) {
            inline else => |*i| i.deinit(alloc),
        }
    }

    pub fn description(self: Image) Description {
        return switch (self) {
            inline else => |i| i.description,
        };
    }
};
