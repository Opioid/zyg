const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Options = struct {
    take: ?[]u8 = null,

    mounts: std.ArrayListUnmanaged([]u8) = .{},

    threads: i32 = 0,

    start_frame: u32 = 0,
    num_frames: u32 = 1,

    pub fn deinit(self: *Options, alloc: *Allocator) void {
        for (self.mounts.items) |mount| {
            alloc.free(mount);
        }

        self.mounts.deinit(alloc);

        if (self.take) |take| {
            alloc.free(take);
        }
    }

    pub fn parse(alloc: *Allocator, args: std.process.ArgIterator) !Options {
        var options = Options{};

        var iter = args;

        if (!iter.skip()) {
            help();
            return options;
        }

        var executed = false;

        var i_i = iter.next(alloc);
        while (i_i) |arg_i| {
            const argument_i = try arg_i;

            const command = argument_i[1..];

            var i_j = iter.next(alloc);
            if (i_j) |arg_j| {
                const argument_j = try arg_j;

                if (isParameter(argument_j)) {
                    try options.handleAll(command, argument_j, alloc);
                    alloc.free(argument_j);

                    executed = true;

                    continue;
                }
            }

            if (!executed) {
                try options.handleAll(command, "", alloc);
            }

            alloc.free(argument_i);
            i_i = i_j;

            executed = false;
        }

        return options;
    }

    fn handleAll(self: *Options, command: []u8, parameter: []u8, alloc: *Allocator) !void {
        if ('-' == command[0]) {
            try self.handle(command[1..], parameter, alloc);
        } else {
            for (command) |_, i| {
                try self.handle(command[i .. i + 1], parameter, alloc);
            }
        }
    }

    fn handle(self: *Options, command: []u8, parameter: []u8, alloc: *Allocator) !void {
        if (std.mem.eql(u8, "help", command) or std.mem.eql(u8, "h", command)) {
            help();
        } else if (std.mem.eql(u8, "frame", command) or std.mem.eql(u8, "f", command)) {
            self.start_frame = std.fmt.parseUnsigned(u32, parameter, 0) catch 0;
        } else if (std.mem.eql(u8, "num-frames", command) or std.mem.eql(u8, "n", command)) {
            self.num_frames = std.fmt.parseUnsigned(u32, parameter, 0) catch 1;
        } else if (std.mem.eql(u8, "input", command) or std.mem.eql(u8, "i", command)) {
            self.take = try alloc.alloc(u8, parameter.len);
            if (self.take) |take| {
                std.mem.copy(u8, take, parameter);
            }
        } else if (std.mem.eql(u8, "mount", command) or std.mem.eql(u8, "m", command)) {
            const mount = try alloc.alloc(u8, parameter.len);
            std.mem.copy(u8, mount, parameter);
            try self.mounts.append(alloc, mount);
        } else if (std.mem.eql(u8, "threads", command) or std.mem.eql(u8, "t", command)) {
            self.threads = std.fmt.parseInt(i32, parameter, 0) catch 0;
        }
    }

    fn isParameter(text: []u8) bool {
        if (text.len <= 1) {
            return true;
        }

        if ('-' == text[0]) {
            if ('-' == text[1]) {
                return false;
            }

            _ = std.fmt.parseInt(i32, text[1..], 0) catch return false;
        }

        return true;
    }

    fn help() void {
        const stdout = std.io.getStdOut().writer();

        const text =
            \\zyg is a global illumination renderer experiment
            \\Usage:
            \\  zyg [OPTION..]
            \\
            \\  -h, --help                     Print help.
            \\  -f, --frame       int          Index of the first frame to render.
            \\                                 The default value is 0.
            \\  -n, --num-frames  int          Number of frames to render.
            \\                                 The default value is 1.
            \\  -i, --input       file/string  Path of the take file to render,
            \\                                 or json-string describing the take.
            \\  -m, --mount       path+        Specifies a mount point for the data directory.
            \\                                 The default value is "../data/"
            \\  -t, --threads     int          Specifies the number of threads used by sprout.
            \\                                 0 creates one thread for each logical CPU.
            \\                                 -x creates as many threads as the number of
            \\                                 logical CPUs minus x.
            \\                                 The default value is 0.
            \\
        ;

        stdout.print(text, .{}) catch return;
    }
};
