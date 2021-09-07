pub const encoding = @import("encoding/encoding.zig");
const ti = @import("typed_image.zig");
pub const Description = ti.Description;
pub const Byte3 = ti.Typed_image(Vec3b);
pub const Float4 = ti.Typed_image(Vec4f);
usingnamespace @import("base").math;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Image = union(enum) {
    Byte3: Byte3,
    Float4: Float4,

    pub fn deinit(self: *Image, alloc: *Allocator) void {
        switch (self.*) {
            .Byte3 => |*i| i.deinit(alloc),
            .Float4 => |*i| i.deinit(alloc),
        }
    }
};
