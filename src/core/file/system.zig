const ReadStream = @import("read_stream.zig").ReadStream;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const System = struct {
    mounts: std.ArrayListUnmanaged([]u8) = .{},

    name_buffer: [256]u8 = undefined,

    pub fn deinit(self: *System, alloc: *Allocator) void {
        for (self.mounts.items) |mount| {
            alloc.free(mount);
        }

        self.mounts.deinit(alloc);
    }

    pub fn pushMount(self: *System, alloc: *Allocator, folder: []const u8) !void {
        const append_slash = folder.len > 0 and folder[folder.len - 1] != '/';
        const buffer_len = if (append_slash) folder.len + 1 else folder.len;

        var buffer = try alloc.alloc(u8, buffer_len);
        std.mem.copy(u8, buffer, folder);

        if (append_slash) {
            buffer[folder.len] = '/';
        }

        try self.mounts.append(alloc, buffer);
    }

    pub fn readStream(self: *System, name: []const u8) !ReadStream {
        for (self.mounts.items) |m| {
            std.mem.copy(u8, self.name_buffer[0..], m);
            std.mem.copy(u8, self.name_buffer[m.len..], name);

            const resolved_name = self.name_buffer[0 .. m.len + name.len];

            const file = std.fs.cwd().openFile(resolved_name, .{}) catch {
                continue;
            };

            return ReadStream.init(file);
        }

        return ReadStream.init(try std.fs.cwd().openFile(name, .{}));
    }
};
