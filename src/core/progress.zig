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
    resolution: u32 = undefined,
    progress: u32 = undefined,
    threshold: f32 = undefined,

    const step = 1.0;

    pub fn start(self: *StdOut, resolution: u32) void {
        self.resolution = resolution;
        self.progress = 0;
        self.threshold = step;
    }

    pub fn tick(self: *StdOut) void {
        if (self.progress >= self.resolution) {
            return;
        }

        self.progress += 1;

        const p = @intToFloat(f32, self.progress) / @intToFloat(f32, self.resolution) * 100.0;
        if (p >= self.threshold) {
            self.threshold += step;

            const stdout = std.io.getStdOut().writer();
            stdout.print("{}%\r", .{@floatToInt(u32, p)}) catch return;
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
