const Resources = @import("manager.zig").Manager;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Null = 0xFFFFFFFF;

pub fn Cache(comptime T: type, comptime P: type) type {
    return struct {
        provider: P,

        resources: std.ArrayListUnmanaged(T),

        const Self = @This();

        pub fn init(alloc: *Allocator, provider: P) Self {
            _ = alloc;
            return .{ .provider = provider, .resources = std.ArrayListUnmanaged(T){} };
        }

        pub fn deinit(self: *Self, alloc: *Allocator) void {
            for (self.resources.items) |*r| {
                r.deinit(alloc);
            }

            self.resources.deinit(alloc);
        }

        pub fn load(self: *Self, alloc: *Allocator, name: []const u8, resources: *Resources) !u32 {
            const item = try self.provider.load(alloc, name, resources);

            try self.resources.append(alloc, item);

            return @intCast(u32, self.resources.items.len - 1);
        }

        pub fn store(self: *Self, alloc: *Allocator, item: T) u32 {
            self.resources.append(alloc, item) catch {
                return Null;
            };

            return @intCast(u32, self.resources.items.len - 1);
        }
    };
}
