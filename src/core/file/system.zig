const ReadStream = @import("read_stream.zig").ReadStream;
const FileReadStream = @import("file_read_stream.zig").FileReadStream;
const GzipReadStream = @import("gzip_read_stream.zig").GzipReadStream;
const fl = @import("file.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const System = struct {
    mounts: std.ArrayList([]u8) = .empty,

    name_buffer: []u8,

    resolved_name_len: u32 = 0,
    frame: u32 = 0,

    stream: FileReadStream = undefined,
    gzip_stream: GzipReadStream = undefined,

    pub fn init(alloc: Allocator) !System {
        const buffer = try alloc.alloc(u8, 256);
        @memset(buffer, 0);

        return System{ .name_buffer = buffer };
    }

    pub fn deinit(self: *System, alloc: Allocator) void {
        alloc.free(self.name_buffer);

        for (self.mounts.items) |mount| {
            alloc.free(mount);
        }

        self.mounts.deinit(alloc);
    }

    pub fn pushMount(self: *System, alloc: Allocator, folder: []const u8) !void {
        const append_slash = folder.len > 0 and folder[folder.len - 1] != '/';
        const buffer_len = if (append_slash) folder.len + 1 else folder.len;

        var buffer = try alloc.alloc(u8, buffer_len);
        @memcpy(buffer[0..folder.len], folder);

        if (append_slash) {
            buffer[folder.len] = '/';
        }

        try self.mounts.append(alloc, buffer);
    }

    pub fn popMount(self: *System, alloc: Allocator) void {
        if (self.mounts.pop()) |mount| {
            alloc.free(mount);
        }
    }

    pub fn readStream(self: *System, alloc: Allocator, name: []const u8) !ReadStream {
        const stream = try self.openReadStream(alloc, name);

        const file_type = try fl.queryType(stream);

        if (.GZIP == file_type) {
            try self.gzip_stream.setStream(stream);
            return ReadStream.initGzip(&self.gzip_stream);
        }

        return stream;
    }

    const FrameMarker = "{FRAME}";

    pub fn frameDependantName(name: []const u8) bool {
        return null != std.mem.indexOf(u8, name, FrameMarker);
    }

    fn openReadStream(self: *System, alloc: Allocator, name: []const u8) !ReadStream {
        var modified_name = name;
        defer {
            if (modified_name.ptr != name.ptr) {
                alloc.free(modified_name);
            }
        }

        if (std.mem.indexOf(u8, name, FrameMarker)) |fm| {
            modified_name = try std.fmt.allocPrint(
                alloc,
                "{s}{d}{s}",
                .{ name[0..fm], self.frame, name[fm + 7 ..] },
            );
        }

        for (self.mounts.items) |m| {
            const resolved_name_len: u32 = @intCast(m.len + modified_name.len);

            if (self.name_buffer.len < resolved_name_len) {
                self.name_buffer = try alloc.realloc(self.name_buffer, resolved_name_len);
            }

            @memcpy(self.name_buffer[0..m.len], m);
            @memcpy(self.name_buffer[m.len..resolved_name_len], modified_name);
            self.resolved_name_len = resolved_name_len;

            const resolved_name = self.name_buffer[0..resolved_name_len];

            const file = std.fs.cwd().openFile(resolved_name, .{}) catch {
                continue;
            };

            self.stream.setFile(file);
            return ReadStream.initFile(&self.stream);
        }

        @memcpy(self.name_buffer[0..modified_name.len], modified_name);
        self.resolved_name_len = @intCast(modified_name.len);

        self.stream.setFile(try std.fs.cwd().openFile(modified_name, .{}));
        return ReadStream.initFile(&self.stream);
    }

    pub fn lastResolvedName(self: *const System) []const u8 {
        return self.name_buffer[0..self.resolved_name_len];
    }

    pub fn cloneLastResolvedName(self: *const System, alloc: Allocator) ![]u8 {
        return try alloc.dupe(u8, self.name_buffer[0..self.resolved_name_len]);
    }
};
