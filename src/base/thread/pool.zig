const std = @import("std");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Atomic;

pub const Pool = struct {
    pub const Context = usize;

    const ParallelProgram = *const fn (context: Context, id: u32) void;
    const RangeProgram = *const fn (context: Context, id: u32, begin: u32, end: u32) void;
    const AsyncProgram = *const fn (context: Context) void;

    const Program = union(enum) { Parallel: ParallelProgram, Range: RangeProgram };

    const SIGNAL_DONE = 0;
    const SIGNAL_QUIT = 1;
    const SIGNAL_WAKE = 2;

    const Unique = struct {
        begin: u32 = 0,
        end: u32 = 0,

        signal: Atomic(u32) = Atomic(u32).init(SIGNAL_DONE),

        thread: std.Thread = undefined,
    };

    const Async = struct {
        context: Context = undefined,
        program: AsyncProgram = undefined,

        signal: Atomic(u32) = Atomic(u32).init(SIGNAL_DONE),

        thread: std.Thread = undefined,
    };

    uniques: []Unique = &.{},

    asyncp: Async = .{},

    context: Context = undefined,
    program: Program = undefined,

    running_parallel: bool = false,
    running_async: bool = false,

    pub fn availableCores(request: i32) u32 {
        const available = @intCast(u32, std.Thread.getCpuCount() catch 1);

        if (request <= 0) {
            const num_threads = @intCast(i32, available) + request;

            return @intCast(u32, std.math.max(num_threads, 1));
        }

        return std.math.min(available, @intCast(u32, std.math.max(request, 1)));
    }

    pub fn configure(self: *Pool, alloc: Allocator, num_threads: u32) !void {
        self.uniques = try alloc.alloc(Unique, num_threads);

        for (self.uniques, 0..) |*u, i| {
            // Initializing u first, seems to get rid of one data race
            u.* = .{};
            u.thread = try std.Thread.spawn(.{}, loop, .{ self, @intCast(u32, i) });
        }

        self.asyncp.thread = try std.Thread.spawn(.{}, asyncLoop, .{&self.asyncp});
    }

    pub fn deinit(self: *Pool, alloc: Allocator) void {
        self.quitAll();

        self.quitAsync();

        alloc.free(self.uniques);
    }

    pub fn numThreads(self: *const Pool) u32 {
        return @intCast(u32, self.uniques.len);
    }

    pub fn runParallel(self: *Pool, context: anytype, program: ParallelProgram, num_tasks_hint: u32) void {
        self.context = @ptrToInt(context);
        self.program = .{ .Parallel = program };

        self.running_parallel = true;

        const num_tasks = if (0 == num_tasks_hint) self.uniques.len else @min(
            @as(usize, num_tasks_hint),
            self.uniques.len,
        );

        for (self.uniques[0..num_tasks]) |*u| {
            u.signal.store(SIGNAL_WAKE, .Monotonic);
            std.Thread.Futex.wake(&u.signal, 1);
        }

        self.waitAll(num_tasks);
    }

    const Cache_line = 64;

    pub fn runRange(
        self: *Pool,
        context: anytype,
        program: RangeProgram,
        begin: u32,
        end: u32,
        item_size_hint: u32,
    ) usize {
        self.context = @ptrToInt(context);
        self.program = .{ .Range = program };

        self.running_parallel = true;

        const range = end - begin;
        const rangef = @intToFloat(f32, range);
        const num_threads = @intToFloat(f32, self.uniques.len);

        const step = if (item_size_hint != 0 and 0 == Cache_line % item_size_hint)
            @floatToInt(u32, @ceil((rangef * @intToFloat(f32, item_size_hint)) / num_threads / Cache_line)) *
                Cache_line / item_size_hint
        else
            @floatToInt(u32, @floor(rangef / num_threads));

        var r = range - @min(step * @intCast(u32, self.uniques.len), range);
        var e = begin;

        var num_tasks = self.uniques.len;

        for (self.uniques, 0..) |*u, i| {
            if (e >= end) {
                num_tasks = i;
                break;
            }

            const b = e;
            e += step;

            if (i < r) {
                e += 1;
            }

            u.begin = b;
            u.end = std.math.min(e, end);
            u.signal.store(SIGNAL_WAKE, .Release);
            std.Thread.Futex.wake(&u.signal, 1);
        }

        self.waitAll(num_tasks);

        return num_tasks;
    }

    pub fn runAsync(self: *Pool, context: anytype, program: AsyncProgram) void {
        self.waitAsync();

        self.asyncp.context = @ptrToInt(context);
        self.asyncp.program = program;
        self.asyncp.signal.store(SIGNAL_WAKE, .Release);
        std.Thread.Futex.wake(&self.asyncp.signal, 1);
    }

    pub fn runningAsync(self: *const Pool) bool {
        return SIGNAL_DONE != self.asyncp.signal.load(.Acquire);
    }

    fn quitAll(self: *Pool) void {
        for (self.uniques) |*u| {
            u.signal.store(SIGNAL_QUIT, .Monotonic);
            std.Thread.Futex.wake(&u.signal, 1);
            u.thread.join();
        }
    }

    fn quitAsync(self: *Pool) void {
        self.asyncp.signal.store(SIGNAL_QUIT, .Monotonic);
        std.Thread.Futex.wake(&self.asyncp.signal, 1);
        self.asyncp.thread.join();
    }

    fn waitAll(self: *Pool, num: usize) void {
        for (self.uniques[0..num]) |*u| {
            while (true) {
                const signal = u.signal.load(.Acquire);
                if (signal == SIGNAL_DONE) {
                    break;
                }

                std.Thread.Futex.wait(&u.signal, signal);
            }
        }

        self.running_parallel = false;
    }

    pub fn waitAsync(self: *Pool) void {
        while (true) {
            const signal = self.asyncp.signal.load(.Acquire);
            if (signal == SIGNAL_DONE) {
                break;
            }

            std.Thread.Futex.wait(&self.asyncp.signal, signal);
        }
    }

    fn loop(self: *Pool, id: u32) void {
        var u = &self.uniques[id];

        while (true) {
            while (true) {
                const signal = u.signal.load(.Acquire);
                if (SIGNAL_QUIT == signal) {
                    return;
                }

                if (SIGNAL_WAKE == signal) {
                    break;
                }

                std.Thread.Futex.wait(&u.signal, signal);
            }

            switch (self.program) {
                .Parallel => |p| p(self.context, id),
                .Range => |p| p(self.context, id, u.begin, u.end),
            }

            u.signal.store(SIGNAL_DONE, .Release);
            std.Thread.Futex.wake(&u.signal, 1);
        }
    }

    fn asyncLoop(self: *Async) void {
        while (true) {
            while (true) {
                const signal = self.signal.load(.Acquire);
                if (SIGNAL_QUIT == signal) {
                    return;
                }

                if (SIGNAL_WAKE == signal) {
                    break;
                }

                std.Thread.Futex.wait(&self.signal, signal);
            }

            self.program(self.context);

            self.signal.store(SIGNAL_DONE, .Release);
            std.Thread.Futex.wake(&self.signal, 1);
        }
    }
};
