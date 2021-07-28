const std = @import("std");
const Allocator = std.mem.Allocator;

const Unique = struct {
    wake_signal: std.Thread.Condition = .{},
    done_signal: std.Thread.Condition = .{},

    mutex: std.Thread.Mutex = .{},

    wake: bool = false,
};

pub const Pool = struct {
    uniques: []Unique = &.{},
    threads: []std.Thread = &.{},

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
        self.wake_all();

        for (self.threads) |thread| {
            thread.join();
        }

        alloc.free(self.threads);
        alloc.free(self.uniques);
    }

    fn wake_all(self: *const Pool) void {
        for (self.uniques) |*u| {
            std.debug.print("we wait\n", .{});

            const lock = u.mutex.acquire();
            u.wake = true;
            lock.release();

            u.wake_signal.signal();
        }
    }

    fn loop(self: *Pool, id: u32) void {
        var u = &self.uniques[id];

        const lock = u.mutex.acquire();

        std.debug.print("We come here\n", .{});

        while (!u.wake) {
            u.wake_signal.wait(&u.mutex);
        }

        u.wake = false;
        lock.release();

        std.debug.print("I'm thread {}!\n", .{id});
    }
};
