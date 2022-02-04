const std = @import("std");

pub const Level = enum {
    Info,
    Warning,
    Error,
};

pub const Log = union(enum) {
    StdOut: StdOut,
    CFunc: CFunc,

    pub fn post(self: *Log, comptime level: Level, comptime format: []const u8, args: anytype) void {
        switch (self.*) {
            .StdOut => StdOut.post(level, format, args),
            .CFunc => |*c| c.post(level, format, args),
        }
    }
};

pub const StdOut = struct {
    pub fn post(comptime level: Level, comptime format: []const u8, args: anytype) void {
        const prefix = switch (level) {
            .Warning => "Warning: ",
            .Error => "Error: ",
            else => "",
        };

        std.debug.getStderrMutex().lock();
        defer std.debug.getStderrMutex().unlock();
        nosuspend std.io.getStdOut().writer().print(prefix ++ format ++ "\n", args) catch return;
    }
};

pub const CFunc = struct {
    pub const Func = fn (level: c_uint, text: [*:0]u8) callconv(.C) void;

    func: Func,

    buffer: [256]u8 = undefined,

    const Self = @This();

    pub fn post(self: *Self, comptime level: Level, comptime format: []const u8, args: anytype) void {
        var line = std.fmt.bufPrintZ(&self.buffer, format, args) catch return;

        self.func(@enumToInt(level), line);
    }
};

pub var log: Log = .{ .StdOut = .{} };

pub fn info(comptime format: []const u8, args: anytype) void {
    log.post(.Info, format, args);
}

pub fn warning(comptime format: []const u8, args: anytype) void {
    log.post(.Warning, format, args);
}

pub fn err(comptime format: []const u8, args: anytype) void {
    log.post(.Error, format, args);
}
