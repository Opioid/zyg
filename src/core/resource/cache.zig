const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Cache(comptime T: type) type {
    return struct {
        resources: std.ArrayListUnmanaged(T),

        pub fn init(alloc: *Allocator) Cache(T) {
            _ = alloc;
            return .{ .resources = std.ArrayListUnmanaged(T){} };
        }

        pub fn deinit(self: *Cache(T), alloc: *Allocator) void {
            self.resources.deinit(alloc);
        }

        pub fn store(self: *Cache(T), alloc: *Allocator, item: T) !u32 {
            try self.resources.append(alloc, item);

            return @intCast(u32, self.resources.items.len - 1);
        }
    };
}
