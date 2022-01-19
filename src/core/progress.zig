const std = @import("std");

const step = 1.0;

pub const StdOut = struct {
    resolution: u32 = undefined,
    progress: u32 = undefined,
    threshold: f32 = undefined,

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
