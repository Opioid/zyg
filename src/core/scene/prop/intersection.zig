const shape = @import("../shape/intersection.zig");

pub const Intersection = struct {
    geo: shape.Intersection = undefined,

    prop: u32 = undefined,
};
