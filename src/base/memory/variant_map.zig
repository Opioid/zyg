const std = @import("std");
const Allocator = std.mem.Allocator;

pub const VariantMap = struct {
    const Variant = union(enum) {
        Bool: bool,
        UInt: u32,
    };

    map: std.StringHashMapUnmanaged(Variant) = .{},

    const Self = @This();

    pub fn deinit(self: *Self, alloc: *Allocator) void {
        self.map.deinit(alloc);
    }

    pub fn cloneExcept(self: Self, alloc: *Allocator, key: []const u8) !Self {
        var result = VariantMap{};

        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            const k = entry.key_ptr.*;
            if (!std.mem.eql(u8, key, k)) {
                try result.map.put(alloc, k, entry.value_ptr.*);
            }
        }

        return result;
    }

    pub fn query(self: Self, comptime T: type, key: []const u8) ?T {
        if (self.map.get(key)) |v| {
            switch (v) {
                .Bool => |b| {
                    return if (T == bool) b else null;
                },
                .UInt => |ui| {
                    if (T == u32) {
                        return ui;
                    }

                    return switch (@typeInfo(T)) {
                        .Enum => @intToEnum(T, ui),
                        else => null,
                    };
                },
            }
        }

        return null;
    }

    pub fn queryOrDef(self: Self, key: []const u8, def: anytype) @TypeOf(def) {
        return self.query(@TypeOf(def), key) orelse def;
    }

    pub fn set(self: *Self, alloc: *Allocator, key: []const u8, val: anytype) !void {
        switch (@typeInfo(@TypeOf(val))) {
            .Bool => {
                try self.map.put(alloc, key, .{ .Bool = val });
            },
            .Enum => {
                try self.map.put(alloc, key, .{ .UInt = @as(u32, @enumToInt(val)) });
            },
            else => {},
        }
    }
};
