const math = @import("../math/vector4.zig");
const Vec4i = math.Vec4i;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const VariantMap = struct {
    const Variant = union(enum) {
        Bool: bool,
        UInt: u32,
        Vec4i: Vec4i,

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
                .Vec4i => |s| switch (other) {
                    .Vec4i => |o| math.equal(s, o),
                    else => false,
                },
            };
        }

        pub fn hash(self: Variant, hasher: anytype) void {
            const et = @intFromEnum(self);
            hasher.update(std.mem.asBytes(&et));

            switch (self) {
                inline else => |v| hasher.update(std.mem.asBytes(&v)),
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
        if (self.map.get(key)) |val| {
            switch (val) {
                .Bool => |b| {
                    return if (T == bool) b else null;
                },
                .UInt => |ui| {
                    if (T == u32) {
                        return ui;
                    }

                    return switch (@typeInfo(T)) {
                        .@"enum" => @enumFromInt(ui),
                        else => null,
                    };
                },
                .Vec4i => |v| {
                    return if (T == Vec4i) v else null;
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
            .bool => try self.map.put(alloc, key, .{ .Bool = val }),
            .@"enum" => try self.map.put(alloc, key, .{ .UInt = @as(u32, @intFromEnum(val)) }),
            .vector => try self.map.put(alloc, key, .{ .Vec4i = val }),
            else => {},
        }
    }
};
