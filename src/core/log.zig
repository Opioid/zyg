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
    pub const Func = fn (level: u32, text: [*:0]const u8) void;

    func: *Func,

    buffer: [256]u8 = undefined,

    const Self = @This();

    pub fn post(self: *Self, comptime level: Level, comptime format: []const u8, args: anytype) void {
        var line = std.fmt.bufPrint(&self.buffer, format, args) catch return;
        self.buffer[line.len] = 0;
        const slice = self.buffer[0..line.len :0];

        std.debug.print("We came here {s}\n", .{slice});

        _ = level;
        self.func.*(0, slice);

        // _ = self;
        // _ = level;
        // _ = format;
        // _ = args;

        // std.debug.print("We came here {s}\n", .{slice});
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
