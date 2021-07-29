const View = @import("../take/take.zig").View;
const Scene = @import("../scene/scene.zig").Scene;
const Worker = @import("worker.zig").Worker;
const TileQueue = @import("tile_queue.zig").TileQueue;

const img = @import("../image/image.zig");
const progress = @import("../progress/std_out.zig");

const base = @import("base");
usingnamespace base;
usingnamespace base.math;

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const ThreadContext = thread.Pool.Context;

pub const Driver = struct {
    threads: *thread.Pool,

    view: *View = undefined,
    scene: *Scene = undefined,

    workers: []Worker = &.{},

    tiles: TileQueue = undefined,

    target: img.Float4 = .{},

    progressor: progress.StdOut = undefined,

    pub fn init(alloc: *Allocator, threads: *thread.Pool) !Driver {
        return Driver{
            .threads = threads,
            .workers = try alloc.alloc(Worker, threads.numThreads()),
        };
    }

    pub fn deinit(self: *Driver, alloc: *Allocator) void {
        self.target.deinit(alloc);
        alloc.free(self.workers);
    }

    pub fn configure(self: *Driver, alloc: *Allocator, view: *View, scene: *Scene) !void {
        self.view = view;
        self.scene = scene;

        const camera = &self.view.camera;

        const dim = camera.sensorDimensions();

        try camera.sensor.resize(alloc, dim);

        for (self.workers) |*w| {
            w.configure(view, scene);
        }

        self.tiles.configure(camera.crop, 32, 0);

        try self.target.resize(alloc, img.Description.init2D(dim));
    }

    pub fn render(self: *Driver) void {
        var camera = &self.view.camera;

        const camera_pos = self.scene.propWorldPosition(camera.entity);

        self.scene.compile(camera_pos);

        camera.update();

        camera.sensor.clear(0.0);

        self.progressor.start(self.tiles.size());

        self.tiles.restart();

        self.threads.runParallel(self, renderTiles);
    }

    pub fn exportFrame(self: *Driver) void {
        self.view.camera.sensor.resolve(&self.target);
    }

    fn renderTiles(context: *ThreadContext, id: u32) void {
        const self = @ptrCast(*Driver, context);

        while (self.tiles.pop()) |tile| {
            self.workers[id].render(tile);

            self.progressor.tick();
        }
    }
};
