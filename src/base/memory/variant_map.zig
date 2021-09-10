const std = @import("std");
const Allocator = std.mem.Allocator;

pub const VariantMap = struct {
    const Variant = union(enum) {
        UInt: u32,
    };

    map: std.StringHashMapUnmanaged(Variant) = .{},

    const Self = @This();

    pub fn deinit(self: *Self, alloc: *Allocator) void {
        self.map.deinit(alloc);
    }

    pub fn query(self: Self, key: []const u8, def: anytype) @TypeOf(def) {
        const td = @TypeOf(def);

        if (self.map.get(key)) |v| {
            switch (v) {
                .UInt => |ui| {
                    if (td == u32) {
                        return ui;
                    }

                    return switch (@typeInfo(td)) {
                        .Enum => @intToEnum(td, ui),
                        else => def,
                    };
                },
            }
        }

        return def;
    }

    pub fn set(self: *Self, alloc: *Allocator, key: []const u8, val: anytype) !void {
        switch (@typeInfo(@TypeOf(val))) {
            .Enum => {
                try self.map.put(alloc, key, .{ .UInt = @as(u32, @enumToInt(val)) });
            },
            else => {},
        }
    }
};
