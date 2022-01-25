const std = @import("std");
const Allocator = std.mem.Allocator;

pub const VariantMap = struct {
    const Variant = union(enum) {
        Bool: bool,
        UInt: u32,

        pub fn eql(self: Variant, other: Variant) bool {
            return switch (self) {
                .Bool => |s| switch (other) {
                    .Bool => |o| s == o,
                    else => false,
                },
                .UInt => |s| switch (other) {
                    .UInt => |o| s == o,
                    else => false,
                },
            };
        }

        pub fn hash(self: Variant, hasher: anytype) void {
            const et = @enumToInt(self);
            hasher.update(std.mem.asBytes(&et));

            switch (self) {
                .Bool => |b| hasher.update(std.mem.asBytes(&b)),
                .UInt => |i| hasher.update(std.mem.asBytes(&i)),
            }
        }
    };

    map: std.StringHashMapUnmanaged(Variant) = .{},

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.map.deinit(alloc);
    }

    pub fn clone(self: Self, alloc: Allocator) !Self {
        return VariantMap{ .map = try self.map.clone(alloc) };
    }

    pub fn cloneExcept(self: Self, alloc: Allocator, key: []const u8) !Self {
        var map = std.StringHashMapUnmanaged(Variant){};

        try map.ensureTotalCapacity(alloc, self.map.count());

        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            const k = entry.key_ptr.*;
            if (!std.mem.eql(u8, key, k)) {
                try map.put(alloc, k, entry.value_ptr.*);
            }
        }

        return VariantMap{ .map = map };
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

    pub fn set(self: *Self, alloc: Allocator, key: []const u8, val: anytype) !void {
        switch (@typeInfo(@TypeOf(val))) {
            .Bool => try self.map.put(alloc, key, .{ .Bool = val }),
            .Enum => try self.map.put(alloc, key, .{ .UInt = @as(u32, @enumToInt(val)) }),
            else => {},
        }
    }
};
