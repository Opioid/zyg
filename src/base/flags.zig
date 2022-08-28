pub fn Flags(comptime T: type) type {
    return struct {
        const Type = @typeInfo(T).Enum.tag_type;

        values: Type = 0,

        const Self = @This();

        pub inline fn init1(a: T) Self {
            return .{ .values = @enumToInt(a) };
        }

        pub inline fn init2(a: T, b: T, b_value: bool) Self {
            return .{ .values = @enumToInt(a) | (if (b_value) @enumToInt(b) else 0) };
        }

        pub inline fn is(self: Self, flag: T) bool {
            return 0 != (self.values & @enumToInt(flag));
        }

        pub inline fn no(self: Self, flag: T) bool {
            return 0 == (self.values & @enumToInt(flag));
        }

        pub inline fn no2(self: Self, flag0: T, flag1: T) bool {
            return 0 == (self.values & (@enumToInt(flag0) | @enumToInt(flag1)));
        }

        pub inline fn equal(self: Self, flag: T) bool {
            return self.values == @enumToInt(flag);
        }

        pub inline fn set(self: *Self, flag: T, value: bool) void {
            if (value) {
                self.values |= @enumToInt(flag);
            } else {
                self.values &= ~@enumToInt(flag);
            }
        }

        pub inline fn andSet(self: *Self, flag: T, value: bool) void {
            if (self.is(flag) and !value) {
                self.values &= ~@enumToInt(flag);
            }
        }

        pub inline fn orSet(self: *Self, flag: T, value: bool) void {
            if (self.no(flag) and value) {
                self.values |= @enumToInt(flag);
            }
        }

        pub inline fn unset(self: *Self, flag: T) void {
            self.values &= ~@enumToInt(flag);
        }

        pub inline fn clear(self: *Self) void {
            self.values = 0;
        }

        pub inline fn clearWith(self: *Self, flag: T) void {
            self.values = @enumToInt(flag);
        }
    };
}
