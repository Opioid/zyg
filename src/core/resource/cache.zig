const Resources = @import("manager.zig").Manager;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Null = 0xFFFFFFFF;

pub fn Cache(comptime T: type, comptime P: type) type {
    return struct {
        provider: P,
        resources: std.ArrayListUnmanaged(T),
        entries: std.StringHashMap(u32),

        const Self = @This();

        pub fn init(alloc: *Allocator, provider: P) Self {
            return .{
                .provider = provider,
                .resources = std.ArrayListUnmanaged(T){},
                .entries = std.StringHashMap(u32).init(alloc),
            };
        }

        pub fn deinit(self: *Self, alloc: *Allocator) void {
            self.entries.deinit();

            for (self.resources.items) |*r| {
                r.deinit(alloc);
            }

            self.resources.deinit(alloc);
        }

        pub fn load(self: *Self, alloc: *Allocator, name: []const u8, resources: *Resources) !u32 {
            if (self.entries.get(name)) |entry| {
                return entry;
            }

            const item = try self.provider.load(alloc, name, resources);

            try self.resources.append(alloc, item);

            const id = @intCast(u32, self.resources.items.len - 1);

            try self.entries.put(name, id);

            return id;
        }

        pub fn store(self: *Self, alloc: *Allocator, item: T) u32 {
            self.resources.append(alloc, item) catch {
                return Null;
            };

            return @intCast(u32, self.resources.items.len - 1);
        }
    };
}
