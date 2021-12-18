const base = @import("base");
const Threads = base.thread.Pool;

pub const Map = struct {
    const Self = @This();

    pub fn start(self: *Self) void {
        _ = self;
    }

    pub fn compileIteration(self: *Self, num_photons: u32, num_paths: u64, threads: *Threads) u32 {
        _ = self;
        _ = num_photons;
        _ = num_paths;
        _ = threads;

        return 0;
    }

    pub fn compileFinalize(self: *Self) void {
        _ = self;
    }
};
