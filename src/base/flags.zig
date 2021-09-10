pub fn Flags(comptime T: type) type {
    return struct {
        const Type = @typeInfo(T).Enum.tag_type;

        values: Type = 0,

        const Self = @This();

        pub fn init1(a: T) Self {
            return .{ .values = @enumToInt(a) };
        }

        pub fn is(self: Self, flag: T) bool {
            return 0 != (self.values & @enumToInt(flag));
        }
    };
}
