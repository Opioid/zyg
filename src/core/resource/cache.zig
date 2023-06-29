const log = @import("../log.zig");
const Resources = @import("manager.zig").Manager;
const Filesystem = @import("../file/system.zig").System;
const Variants = @import("base").memory.VariantMap;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Null = 0xFFFFFFFF;

const Key = struct {
    name: []const u8,
    options: Variants,

    const Self = @This();

    pub fn clone(self: Self, alloc: Allocator) !Self {
        return Self{
            .name = try alloc.dupe(u8, self.name),
            .options = try self.options.clone(alloc),
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.options.deinit(alloc);
        alloc.free(self.name);
    }
};

const KeyContext = struct {
    const Self = @This();

    pub fn hash(self: Self, k: Key) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);

        hasher.update(k.name);

        var iter = k.options.map.iterator();
        while (iter.next()) |entry| {
            hasher.update(entry.key_ptr.*);
            entry.value_ptr.hash(&hasher);
        }

        return hasher.final();
    }

    pub fn eql(self: Self, a: Key, b: Key) bool {
        _ = self;

        if (!std.mem.eql(u8, a.name, b.name)) {
            return false;
        }

        if (a.options.map.count() != b.options.map.count()) {
            return false;
        }

        var a_iter = a.options.map.iterator();
        var b_iter = b.options.map.iterator();
        while (a_iter.next()) |a_entry| {
            if (b_iter.next()) |b_entry| {
                if (!std.mem.eql(u8, a_entry.key_ptr.*, b_entry.key_ptr.*)) {
                    return false;
                }

                if (!a_entry.value_ptr.eql(b_entry.value_ptr.*)) {
                    return false;
                }
            } else {
                return false;
            }
        }

        return true;
    }
};

const Entry = struct {
    id: u32,
    source_name: []u8 = &.{},
};

const List = std.ArrayListUnmanaged;
const EntryHashMap = std.HashMapUnmanaged(Key, Entry, KeyContext, 80);
const MetaHashMap = std.AutoHashMapUnmanaged(u32, Variants);

pub fn Cache(comptime T: type, comptime P: type) type {
    return struct {
        provider: P,
        resources: *List(T),
        entries: EntryHashMap = .{},
        metadata: MetaHashMap = .{},

        const Self = @This();

        pub fn init(provider: P, resources: *List(T)) Self {
            return .{ .provider = provider, .resources = resources };
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            {
                var iter = self.metadata.iterator();
                while (iter.next()) |entry| {
                    entry.value_ptr.deinit(alloc);
                }
            }

            self.metadata.deinit(alloc);

            {
                var iter = self.entries.iterator();
                while (iter.next()) |entry| {
                    entry.key_ptr.deinit(alloc);
                    alloc.free(entry.value_ptr.source_name);
                }
            }

            self.entries.deinit(alloc);

            self.provider.deinit(alloc);
        }

        pub fn reloadFrameDependant(self: *Self, alloc: Allocator, resources: *Resources) !bool {
            var deprecated = false;

            var iter = self.entries.iterator();
            while (iter.next()) |entry| {
                const filename = entry.key_ptr.name;

                if (Filesystem.frameDependantName(filename)) {
                    const item = self.provider.loadFile(alloc, filename, entry.key_ptr.options, resources) catch |e| {
                        log.err("Cannot re-load file \"{s}\": {}", .{ filename, e });
                        return e;
                    };

                    const id = entry.value_ptr.id;
                    self.resources.items[id].deinit(alloc);
                    self.resources.items[id] = item.data;
                    deprecated = true;

                    if (self.metadata.getEntry(id)) |e| {
                        e.value_ptr.deinit(alloc);
                    }

                    if (item.meta.map.count() > 0) {
                        try self.metadata.put(alloc, id, item.meta);
                    }
                }
            }

            return deprecated;
        }

        pub fn loadFile(
            self: *Self,
            alloc: Allocator,
            name: []const u8,
            options: Variants,
            resources: *Resources,
        ) !u32 {
            const key = Key{ .name = name, .options = options };
            if (self.entries.get(key)) |entry| {
                return entry.id;
            }

            const item = self.provider.loadFile(alloc, name, options, resources) catch |e| {
                log.err("Could not load file \"{s}\": {}", .{ name, e });
                return e;
            };

            try self.resources.append(alloc, item.data);
            const id = @as(u32, @intCast(self.resources.items.len - 1));

            try self.entries.put(
                alloc,
                try key.clone(alloc),
                .{ .id = id, .source_name = try resources.fs.cloneLastResolvedName(alloc) },
            );

            if (item.meta.map.count() > 0) {
                try self.metadata.put(alloc, id, item.meta);
            }

            return id;
        }

        pub fn loadData(
            self: *Self,
            alloc: Allocator,
            id: u32,
            data: *align(8) const anyopaque,
            options: Variants,
            resources: *Resources,
        ) !u32 {
            const item = try self.provider.loadData(alloc, data, options, resources);

            return try self.store(alloc, id, item);
        }

        pub fn get(self: *const Self, id: u32) ?*T {
            if (id < self.resources.items.len) {
                return &self.resources.items[id];
            }

            return null;
        }

        pub fn getLast(self: *const Self) ?*T {
            return self.get(@as(u32, @intCast(self.resources.items.len - 1)));
        }

        pub fn getByName(self: *const Self, name: []const u8, options: Variants) ?u32 {
            const key = Key{ .name = name, .options = options };
            if (self.entries.get(key)) |entry| {
                return entry.id;
            }

            return null;
        }

        pub fn meta(self: *const Self, id: u32) ?Variants {
            return self.metadata.get(id);
        }

        pub fn store(self: *Self, alloc: Allocator, id: u32, item: T) !u32 {
            if (id >= self.resources.items.len) {
                try self.resources.append(alloc, item);
                return @as(u32, @intCast(self.resources.items.len - 1));
            } else {
                self.resources.items[id].deinit(alloc);
                self.resources.items[id] = item;
                return id;
            }
        }

        pub fn associate(self: *Self, alloc: Allocator, id: u32, name: []const u8, options: Variants) !void {
            if (0 != name.len) {
                const key = Key{ .name = name, .options = options };
                try self.entries.put(alloc, try key.clone(alloc), .{ .id = id });
            }
        }
    };
}
