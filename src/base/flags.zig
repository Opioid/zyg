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

        pub fn no(self: Self, flag: T) bool {
            return 0 == (self.values & @enumToInt(flag));
        }

        pub fn equals(self: Self, flag: T) bool {
            return self.values == @enumToInt(flag);
        }

        pub fn set(self: *Self, flag: T, value: bool) void {
            if (value) {
                self.values |= @enumToInt(flag);
            } else {
                self.values &= ~@enumToInt(flag);
            }
        }

        pub fn clear(self: *Self) void {
            self.values = 0;
        }

        pub fn clearWith(self: *Self, flag: T) void {
            self.values = @enumToInt(flag);
        }
    };
}