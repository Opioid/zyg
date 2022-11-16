const Variants = @import("base").memory.VariantMap;

pub fn Result(comptime T: type) type {
    return struct {
        data: T,
        meta: Variants = .{},
    };
}
