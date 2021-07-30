const std = @import("std");
const Allocator = std.mem.Allocator;

const Unique = struct {
    wake_signal: std.Thread.Condition = .{},
    done_signal: std.Thread.Condition = .{},

    mutex: std.Thread.Mutex = .{},

    wake: bool = false,
};

pub const Pool = struct {
    pub const Context = u64;

    const ParallelProgram = fn (context: *Context, id: u32) void;

    uniques: []Unique = &.{},
    threads: []std.Thread = &.{},

    parallel_context: *Context,
    parallel_program: ParallelProgram,

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
        self.runParallelInt(@ptrCast(*Context, context), program);
    }

    fn runParallelInt(self: *Pool, context: *Context, program: ParallelProgram) void {
        self.parallel_context = context;
        self.parallel_program = program;

        self.wakeAll();

        self.waitAll();
    }

    fn wakeAll(self: *const Pool) void {
        for (self.uniques) |*u| {
            const lock = u.mutex.acquire();
            u.wake = true;
            lock.release();

            u.wake_signal.signal();
        }
    }

    fn waitAll(self: *const Pool) void {
        for (self.uniques) |*u| {
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

            self.parallel_program(self.parallel_context, id);

            u.wake = false;
            u.done_signal.signal();
        }
    }
};
