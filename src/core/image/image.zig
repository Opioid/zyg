pub const encoding = @import("encoding/encoding.zig");

usingnamespace @import("base").math;

const typed_image = @import("typed_image.zig");

pub const Description = typed_image.Description;

pub const Float4 = typed_image.Typed_image(Vec4f);
