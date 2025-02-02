const std = @import("std");

pub const Progressor = union(enum) {
    StdOut: StdOut,
    CFunc: CFunc,
    Null,

    const Self = @This();

    pub fn start(self: *Self, resolution: u32) void {
        switch (self.*) {
            .StdOut => |*p| p.start(resolution),
            .CFunc => |p| p.start(resolution),
            .Null => {},
        }
    }

    pub fn tick(self: *Self) void {
        switch (self.*) {
            .StdOut => |*p| p.tick(),
            .CFunc => |p| p.tick(),
            .Null => {},
        }
    }
};

pub const StdOut = struct {
    resolution: u32,
    progress: u32,
    threshold: f32,

    const Step = 1.0;

    pub fn start(self: *StdOut, resolution: u32) void {
        self.resolution = resolution;
        self.progress = 0;
        self.threshold = Step;
    }

    pub fn tick(self: *StdOut) void {
        if (self.progress >= self.resolution) {
            return;
        }

        self.progress += 1;

        const p = @as(f32, @floatFromInt(self.progress)) / @as(f32, @floatFromInt(self.resolution)) * 100.0;
        if (p >= self.threshold) {
            self.threshold += Step;

            const stdout = std.io.getStdOut().writer();
            stdout.print("{}%\r", .{@as(u32, @intFromFloat(p))}) catch return;
        }
    }
};

pub const CFunc = struct {
    pub const Start = *const fn (resolution: u32) callconv(.C) void;
    pub const Tick = *const fn () callconv(.C) void;

    start_func: Start,
    tick_func: Tick,

    const Self = @This();

    pub fn start(self: Self, resolution: u32) void {
        self.start_func(resolution);
    }

    pub fn tick(self: Self) void {
        self.tick_func();
    }
};
