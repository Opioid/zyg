const std = @import("std");
const Allocator = std.mem.Allocator;

const Unique = struct {
    begin: u32 = 0,
    end: u32 = 0,

    wake_signal: std.Thread.Condition = .{},
    done_signal: std.Thread.Condition = .{},

    mutex: std.Thread.Mutex = .{},

    wake: bool = false,
};

pub const Pool = struct {
    pub const Context = usize;

    const ParallelProgram = fn (context: Context, id: u32) void;
    const RangeProgram = fn (context: Context, id: u32, begin: u32, end: u32) void;

    const Program = union(enum) { Parallel: ParallelProgram, Range: RangeProgram };

    uniques: []Unique = &.{},
    threads: []std.Thread = &.{},

    context: Context = undefined,
    program: Program = undefined,

    quit: bool = false,

    pub fn availableCores(request: i32) u32 {
        const available = @intCast(u32, std.Thread.getCpuCount() catch 1);

        if (request <= 0) {
            const num_threads = @intCast(i32, available) + request;

            return @intCast(u32, std.math.max(num_threads, 1));
        }

        return std.math.min(available, @intCast(u32, std.math.max(request, 1)));
    }

    pub fn configure(self: *Pool, alloc: *Allocator, num_threads: u32) !void {
        self.uniques = try alloc.alloc(Unique, num_threads);

        for (self.uniques) |*u| {
            u.* = .{};
        }

        self.threads = try alloc.alloc(std.Thread, num_threads);

        for (self.threads) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, loop, .{ self, @intCast(u32, i) });
        }
    }

    pub fn deinit(self: *Pool, alloc: *Allocator) void {
        self.quit = true;

        self.wakeAll();

        for (self.threads) |thread| {
            thread.join();
        }

        alloc.free(self.threads);
        alloc.free(self.uniques);
    }

    pub fn numThreads(self: Pool) u32 {
        return @intCast(u32, self.threads.len);
    }

    pub fn runParallel(self: *Pool, context: anytype, program: ParallelProgram) void {
        self.runParallelInt(@ptrToInt(context), program);
    }

    pub fn runRange(self: *Pool, context: anytype, program: RangeProgram, begin: u32, end: u32) void {
        self.runRangeInt(@ptrToInt(context), program, begin, end);
    }

    fn runParallelInt(self: *Pool, context: Context, program: ParallelProgram) void {
        self.context = context;
        self.program = .{ .Parallel = program };

        self.wakeAll();

        self.waitAll(self.uniques.len);
    }

    fn runRangeInt(self: *Pool, context: Context, program: RangeProgram, begin: u32, end: u32) void {
        self.context = context;
        self.program = .{ .Range = program };

        const num = self.wakeAllRange(begin, end);

        self.waitAll(num);
    }

    fn wakeAll(self: Pool) void {
        for (self.uniques) |*u| {
            const lock = u.mutex.acquire();
            u.wake = true;
            lock.release();
            u.wake_signal.signal();
        }
    }

    fn wakeAllRange(self: Pool, begin: u32, end: u32) usize {
        const range = @intToFloat(f32, end - begin);
        const num_threads = @intToFloat(f32, self.threads.len);

        const step = @floatToInt(u32, @ceil(range / num_threads));

        var e = begin;

        for (self.uniques) |*u, i| {
            const b = e;
            e += step;

            if (b >= end) {
                return i;
            }

            const lock = u.mutex.acquire();
            u.begin = b;
            u.end = std.math.min(e, end);
            u.wake = true;
            lock.release();
            u.wake_signal.signal();
        }

        return self.uniques.len;
    }

    fn waitAll(self: Pool, num: usize) void {
        for (self.uniques[0..num]) |*u| {
            const lock = u.mutex.acquire();
            defer lock.release();

            while (u.wake) {
                u.done_signal.wait(&u.mutex);
            }
        }
    }

    fn loop(self: *Pool, id: u32) void {
        var u = &self.uniques[id];

        while (true) {
            const lock = u.mutex.acquire();
            defer lock.release();

            while (!u.wake) {
                u.wake_signal.wait(&u.mutex);
            }

            if (self.quit) {
                break;
            }

            switch (self.program) {
                .Parallel => |p| p(self.context, id),
                .Range => |p| p(self.context, id, u.begin, u.end),
            }

            u.wake = false;
            u.done_signal.signal();
        }
    }
};
