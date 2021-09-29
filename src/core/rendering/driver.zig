const View = @import("../take/take.zig").View;
const Scene = @import("../scene/scene.zig").Scene;
const Worker = @import("worker.zig").Worker;
const TileQueue = @import("tile_queue.zig").TileQueue;
const img = @import("../image/image.zig");
const progress = @import("../progress/std_out.zig");
const base = @import("base");
const chrono = base.chrono;
const Threads = base.thread.Pool;
const ThreadContext = base.thread.Pool.Context;

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const Error = error{
    InvalidSurfaceIntegrator,
};

pub const Driver = struct {
    threads: *Threads,

    view: *View = undefined,
    scene: *Scene = undefined,

    workers: []Worker = &.{},

    tiles: TileQueue = undefined,

    target: img.Float4 = .{},

    progressor: progress.StdOut = undefined,

    pub fn init(alloc: *Allocator, threads: *Threads) !Driver {
        var workers = try alloc.alloc(Worker, threads.numThreads());

        for (workers) |*w| {
            w.* = .{};
        }

        return Driver{
            .threads = threads,
            .workers = workers,
        };
    }

    pub fn deinit(self: *Driver, alloc: *Allocator) void {
        self.target.deinit(alloc);

        for (self.workers) |*w| {
            w.deinit(alloc);
        }

        alloc.free(self.workers);
    }

    pub fn configure(self: *Driver, alloc: *Allocator, view: *View, scene: *Scene) !void {
        const surfaces = view.surfaces orelse return Error.InvalidSurfaceIntegrator;

        self.view = view;
        self.scene = scene;

        const camera = &self.view.camera;

        const dim = camera.sensorDimensions();

        try camera.sensor.resize(alloc, dim);

        for (self.workers) |*w| {
            try w.configure(alloc, camera, scene, view.num_samples_per_pixel, view.samplers, surfaces);
        }

        self.tiles.configure(camera.crop, 32, 0);

        try self.target.resize(alloc, img.Description.init2D(dim));
    }

    pub fn render(self: *Driver, alloc: *Allocator) !void {
        if (0 == self.view.num_samples_per_pixel) {
            return;
        }

        var camera = &self.view.camera;

        const camera_pos = self.scene.propWorldPosition(camera.entity);

        try self.scene.compile(alloc, camera_pos, self.threads);

        camera.update(&self.workers[0].super);

        std.debug.print("Tracing camera rays...\n", .{});

        const start = std.time.milliTimestamp();

        camera.sensor.clear(0.0);

        self.progressor.start(self.tiles.size());

        self.tiles.restart();

        self.threads.runParallel(self, renderTiles, 0);

        std.debug.print("Camera ray time {d:.2} s\n", .{chrono.secondsSince(start)});

        std.debug.print("Render time {d:.2} s\n", .{chrono.secondsSince(start)});

        const pp_start = std.time.milliTimestamp();

        self.view.pipeline.apply(camera.sensor, &self.target, self.threads);

        std.debug.print("Post-process time {d:.2} s\n", .{chrono.secondsSince(pp_start)});
    }

    pub fn exportFrame(self: *Driver) void {
        _ = self;
        //self.view.camera.sensor.resolve(&self.target);
    }

    fn renderTiles(context: ThreadContext, id: u32) void {
        const self = @intToPtr(*Driver, context);

        const num_samples = self.view.num_samples_per_pixel;

        while (self.tiles.pop()) |tile| {
            self.workers[id].render(tile, num_samples);

            self.progressor.tick();
        }
    }
};
