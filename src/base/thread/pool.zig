const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Pool = struct {
    pub const Context = usize;

    const ParallelProgram = fn (context: Context, id: u32) void;
    const RangeProgram = fn (context: Context, id: u32, begin: u32, end: u32) void;
    const AsyncProgram = fn (context: Context) void;

    const Program = union(enum) { Parallel: ParallelProgram, Range: RangeProgram };

    const Unique = struct {
        begin: u32 = 0,
        end: u32 = 0,

        wake_signal: std.Thread.Condition = .{},
        done_signal: std.Thread.Condition = .{},

        mutex: std.Thread.Mutex = .{},

        wake: bool = false,
    };

    const Async = struct {
        context: Context = undefined,
        program: AsyncProgram = undefined,

        wake_signal: std.Thread.Condition = .{},
        done_signal: std.Thread.Condition = .{},

        mutex: std.Thread.Mutex = .{},

        wake: bool = false,
        quit: bool = false,
    };

    uniques: []Unique = &.{},
    threads: []std.Thread = &.{},

    asyncp: Async = .{},
    async_thread: std.Thread = undefined,

    context: Context = undefined,
    program: Program = undefined,

    quit: bool = false,
    running_parallel: bool = false,

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

        for (self.uniques) |*u| {
            u.* = .{};
        }

        self.threads = try alloc.alloc(std.Thread, num_threads);

        for (self.threads) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, loop, .{ self, @intCast(u32, i) });
        }

        self.async_thread = try std.Thread.spawn(.{}, asyncLoop, .{&self.asyncp});
    }

    pub fn deinit(self: *Pool, alloc: Allocator) void {
        self.quit = true;

        _ = self.wakeAll(0);

        for (self.threads) |thread| {
            thread.join();
        }

        self.asyncp.quit = true;
        self.wakeAsync();
        self.async_thread.join();

        alloc.free(self.threads);
        alloc.free(self.uniques);
    }

    pub fn numThreads(self: Pool) u32 {
        return @intCast(u32, self.threads.len);
    }

    pub fn runParallel(self: *Pool, context: anytype, program: ParallelProgram, num_tasks_hint: u32) void {
        self.runParallelInt(@ptrToInt(context), program, num_tasks_hint);
    }

    pub fn runRange(
        self: *Pool,
        context: anytype,
        program: RangeProgram,
        begin: u32,
        end: u32,
        item_size_hint: u32,
    ) usize {
        return self.runRangeInt(@ptrToInt(context), program, begin, end, item_size_hint);
    }

    pub fn runAsync(self: *Pool, context: anytype, program: AsyncProgram) void {
        self.runAsyncInt(@ptrToInt(context), program);
    }

    fn runParallelInt(self: *Pool, context: Context, program: ParallelProgram, num_tasks_hint: u32) void {
        self.context = context;
        self.program = .{ .Parallel = program };

        const num = self.wakeAll(num_tasks_hint);

        self.waitAll(num);
    }

    fn runRangeInt(
        self: *Pool,
        context: Context,
        program: RangeProgram,
        begin: u32,
        end: u32,
        item_size_hint: u32,
    ) usize {
        self.context = context;
        self.program = .{ .Range = program };

        const num = self.wakeAllRange(begin, end, item_size_hint);

        self.waitAll(num);

        return num;
    }

    fn runAsyncInt(self: *Pool, context: Context, program: AsyncProgram) void {
        self.waitAsync();

        self.asyncp.context = context;
        self.asyncp.program = program;

        self.wakeAsync();
    }

    fn wakeAll(self: *Pool, num_tasks_hint: u32) usize {
        self.running_parallel = true;

        const num_tasks = if (0 == num_tasks_hint) self.uniques.len else std.math.min(
            @as(usize, num_tasks_hint),
            self.uniques.len,
        );

        for (self.uniques[0..num_tasks]) |*u| {
            u.mutex.lock();
            u.wake = true;
            u.mutex.unlock();
            u.wake_signal.signal();
        }

        return num_tasks;
    }

    const Cache_line = 64;

    fn wakeAllRange(self: *Pool, begin: u32, end: u32, item_size_hint: u32) usize {
        self.running_parallel = true;

        const range = end - begin;
        const rangef = @intToFloat(f32, range);
        const num_threads = @intToFloat(f32, self.threads.len);

        const step = if (item_size_hint != 0 and 0 == Cache_line % item_size_hint)
            @floatToInt(u32, @ceil((rangef * @intToFloat(f32, item_size_hint)) / num_threads / Cache_line)) *
                Cache_line / item_size_hint
        else
            @floatToInt(u32, @floor(rangef / num_threads));

        var r = range - std.math.min(step * @intCast(u32, self.threads.len), range);
        var e = begin;

        for (self.uniques) |*u, i| {
            if (e >= end) {
                return i;
            }

            const b = e;
            e += step;

            if (i < r) {
                e += 1;
            }

            u.mutex.lock();
            u.begin = b;
            u.end = std.math.min(e, end);
            u.wake = true;
            u.mutex.unlock();
            u.wake_signal.signal();
        }

        return self.uniques.len;
    }

    fn wakeAsync(self: *Pool) void {
        self.asyncp.mutex.lock();
        self.asyncp.wake = true;
        self.asyncp.mutex.unlock();
        self.asyncp.wake_signal.signal();
    }

    fn waitAll(self: *Pool, num: usize) void {
        for (self.uniques[0..num]) |*u| {
            u.mutex.lock();
            defer u.mutex.unlock();

            while (u.wake) {
                u.done_signal.wait(&u.mutex);
            }
        }

        self.running_parallel = false;
    }

    pub fn waitAsync(self: *Pool) void {
        self.asyncp.mutex.lock();
        defer self.asyncp.mutex.unlock();

        while (self.asyncp.wake) {
            self.asyncp.done_signal.wait(&self.asyncp.mutex);
        }
    }

    fn loop(self: *Pool, id: u32) void {
        var u = &self.uniques[id];

        while (true) {
            u.mutex.lock();
            defer u.mutex.unlock();

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

    fn asyncLoop(self: *Async) void {
        while (true) {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (!self.wake) {
                self.wake_signal.wait(&self.mutex);
            }

            if (self.quit) {
                break;
            }

            self.program(self.context);

            self.wake = false;
            self.done_signal.signal();
        }
    }
};
