const Operator = @import("operator.zig").Operator.Class;
const Blur = @import("blur.zig").Blur;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Options = struct {
    pub const Format = enum {
        EXR,
        PNG,
        RGBE,
        TXT,
    };

    inputs: std.ArrayListUnmanaged([]u8) = .empty,
    operator: Operator = .Over,
    format: ?Format = null,
    exposure: f32 = 0.0,
    threads: i32 = 0,

    pub fn deinit(self: *Options, alloc: Allocator) void {
        for (self.inputs.items) |input| {
            alloc.free(input);
        }

        self.inputs.deinit(alloc);
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
        if (std.mem.eql(u8, "add", command)) {
            self.operator = .Add;
        } else if (std.mem.eql(u8, "anaglyph", command)) {
            self.operator = .Anaglyph;
        } else if (std.mem.eql(u8, "avg", command)) {
            self.operator = .Average;
        } else if (std.mem.eql(u8, "blur", command)) {
            const sigma = std.fmt.parseFloat(f32, parameter) catch 1.0;
            self.operator = .{ .Blur = try Blur.init(alloc, sigma) };
        } else if (std.mem.eql(u8, "input", command) or std.mem.eql(u8, "i", command)) {
            const input = try alloc.dupe(u8, parameter);
            try self.inputs.append(alloc, input);
        } else if (std.mem.eql(u8, "diff", command) or std.mem.eql(u8, "d", command)) {
            self.operator = .Diff;
        } else if (std.mem.eql(u8, "exposure", command) or std.mem.eql(u8, "e", command)) {
            self.exposure = std.fmt.parseFloat(f32, parameter) catch 0.0;
        } else if (std.mem.eql(u8, "format", command) or std.mem.eql(u8, "f", command)) {
            if (std.mem.eql(u8, "exr", parameter)) {
                self.format = .EXR;
            } else if (std.mem.eql(u8, "png", parameter)) {
                self.format = .PNG;
            } else if (std.mem.eql(u8, "rgbe", parameter) or std.mem.eql(u8, "hdr", parameter)) {
                self.format = .RGBE;
            } else if (std.mem.eql(u8, "txt", parameter)) {
                self.format = .TXT;
            }
        } else if (std.mem.eql(u8, "help", command) or std.mem.eql(u8, "h", command)) {
            help();
        } else if (std.mem.eql(u8, "max-value", command)) {
            var value: Vec4f = @splat(0.0);

            var ci: u32 = 0;
            var si = std.mem.splitAny(u8, parameter, " ");
            while (si.next()) |cv| {
                value[ci] = std.fmt.parseFloat(f32, cv) catch 0.0;
                ci += 1;

                if (4 == ci) {
                    break;
                }
            }

            self.operator = .{ .MaxValue = value };
        } else if (std.mem.eql(u8, "over", command)) {
            self.operator = .Over;
        } else if (std.mem.eql(u8, "threads", command) or std.mem.eql(u8, "t", command)) {
            self.threads = std.fmt.parseInt(i32, parameter, 0) catch 0;
        } else if (std.mem.eql(u8, "tone", command)) {
            if (std.mem.eql(u8, "aces", parameter)) {
                self.operator = .{ .Tonemap = .ACES };
            } else if (std.mem.eql(u8, "agx", parameter)) {
                self.operator = .{ .Tonemap = .{ .AgX = .Substitute } };
            } else if (std.mem.eql(u8, "pbr", parameter)) {
                self.operator = .{ .Tonemap = .PbrNeutral };
            } else {
                self.operator = .{ .Tonemap = .Linear };
            }
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
        const stdout = std.io.getStdOut().writer();

        const text =
            \\image tool
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
