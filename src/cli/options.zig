const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Options = struct {
    take: []u8 = &.{},

    mounts: std.ArrayListUnmanaged([]u8) = .{},

    threads: i32 = 0,

    start_frame: u32 = 0,
    num_frames: u32 = 1,

    no_tex: bool = false,
    no_tex_dwim: bool = false,
    debug_material: bool = false,

    pub fn deinit(self: *Options, alloc: Allocator) void {
        for (self.mounts.items) |mount| {
            alloc.free(mount);
        }

        self.mounts.deinit(alloc);

        alloc.free(self.take);
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

            var i_j = iter.next();
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
            for (command) |_, i| {
                try self.handle(alloc, command[i .. i + 1], parameter);
            }
        }
    }

    fn handle(self: *Options, alloc: Allocator, command: []const u8, parameter: []const u8) !void {
        if (std.mem.eql(u8, "help", command) or std.mem.eql(u8, "h", command)) {
            help();
        } else if (std.mem.eql(u8, "frame", command) or std.mem.eql(u8, "f", command)) {
            self.start_frame = std.fmt.parseUnsigned(u32, parameter, 0) catch 0;
        } else if (std.mem.eql(u8, "num-frames", command) or std.mem.eql(u8, "n", command)) {
            self.num_frames = std.fmt.parseUnsigned(u32, parameter, 0) catch 1;
        } else if (std.mem.eql(u8, "input", command) or std.mem.eql(u8, "i", command)) {
            alloc.free(self.take);
            self.take = try alloc.dupe(u8, parameter);
        } else if (std.mem.eql(u8, "mount", command) or std.mem.eql(u8, "m", command)) {
            try self.mounts.append(alloc, try alloc.dupe(u8, parameter));
        } else if (std.mem.eql(u8, "threads", command) or std.mem.eql(u8, "t", command)) {
            self.threads = std.fmt.parseInt(i32, parameter, 0) catch 0;
        } else if (std.mem.eql(u8, "no-tex", command)) {
            self.no_tex = true;
        } else if (std.mem.eql(u8, "no-tex-dwim", command)) {
            self.no_tex_dwim = true;
        } else if (std.mem.eql(u8, "debug-mat", command)) {
            self.debug_material = true;
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
            \\  -m, --mount       path         Specifies a mount point for the data directory.
            \\                                 The default value is "../data/"
            \\  -t, --threads     int          Specifies the number of threads used by sprout.
            \\                                 0 creates one thread for each logical CPU.
            \\                                 -x creates as many threads as the number of
            \\                                 logical CPUs minus x.
            \\                                 The default value is 0.
            \\      --no-tex                   Disables loading of all textures.
            \\      --debug-mat                Force all materials to debug material type.
        ;

        stdout.print(text, .{}) catch return;
    }
};
