const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Options = struct {
    project: []u8 = &.{},

    output: []u8 = &.{},

    mounts: std.ArrayListUnmanaged([]u8) = .empty,

    threads: i32 = 0,

    pub fn deinit(self: *Options, alloc: Allocator) void {
        for (self.mounts.items) |mount| {
            alloc.free(mount);
        }

        self.mounts.deinit(alloc);

        alloc.free(self.project);
        alloc.free(self.output);
    }

    pub fn parse(alloc: Allocator, args: std.process.ArgIterator) !Options {
        var options = Options{};

        var iter = args;

        if (!iter.skip()) {
            help();
            return options;
        }

        var executed = false;

        var i_i = iter.next();
        while (i_i) |arg_i| {
            const command = arg_i[1..];

            const i_j = iter.next();
            if (i_j) |arg_j| {
                if (isParameter(arg_j)) {
                    try options.handleAll(alloc, command, arg_j);
                    executed = true;
                    continue;
                }
            }

            if (!executed) {
                try options.handleAll(alloc, command, "");
            }

            i_i = i_j;

            executed = false;
        }

        return options;
    }

    fn handleAll(self: *Options, alloc: Allocator, command: []const u8, parameter: []const u8) !void {
        if ('-' == command[0]) {
            try self.handle(alloc, command[1..], parameter);
        } else {
            for (command, 0..) |_, i| {
                try self.handle(alloc, command[i .. i + 1], parameter);
            }
        }
    }

    fn handle(self: *Options, alloc: Allocator, command: []const u8, parameter: []const u8) !void {
        if (std.mem.eql(u8, "help", command) or std.mem.eql(u8, "h", command)) {
            help();
        } else if (std.mem.eql(u8, "input", command) or std.mem.eql(u8, "i", command)) {
            alloc.free(self.project);
            self.project = try alloc.dupe(u8, parameter);
        } else if (std.mem.eql(u8, "output", command) or std.mem.eql(u8, "o", command)) {
            alloc.free(self.output);
            self.output = try alloc.dupe(u8, parameter);
        } else if (std.mem.eql(u8, "mount", command) or std.mem.eql(u8, "m", command)) {
            try self.mounts.append(alloc, try alloc.dupe(u8, parameter));
        } else if (std.mem.eql(u8, "threads", command) or std.mem.eql(u8, "t", command)) {
            self.threads = std.fmt.parseInt(i32, parameter, 0) catch 0;
        }
    }

    fn isParameter(text: []const u8) bool {
        if (text.len <= 1) {
            return true;
        }

        if ('-' == text[0]) {
            if ('-' == text[1]) {
                return false;
            }

            _ = std.fmt.parseFloat(f32, text[1..]) catch return false;
        }

        return true;
    }

    fn help() void {
        const stdout = std.fs.File.stdout().deprecatedWriter();

        const text =
            \\scatter tool
            \\Usage:
            \\  it [OPTION..]
            \\
            \\  -h, --help           Print help.
            \\
            \\  -i, --input    file  Specifies an input file.
            \\
            \\  -t, --threads  int   Specifies number of threads used by it.
            \\                       0 creates one thread for each logical CPU.
            \\                       -x creates as many threads as number of
            \\                       logical CPUs minus x. Default is 0.
        ;

        stdout.print(text, .{}) catch return;
    }
};
