const std = @import("std");

pub fn parentDirectory(path: []const u8) []const u8 {
    if (0 == path.len) {
        return path;
    }

    const i = std.mem.lastIndexOfScalar(u8, path, '/') orelse (path.len - 1);

    return path[0 .. i + 1];
}
