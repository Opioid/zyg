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

const math = @import("base").math;
const Vec4i = math.Vec4i;

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const Error = error{
    InvalidSurfaceIntegrator,
    InvalidVolumeIntegrator,
};

pub const Driver = struct {
    threads: *Threads,

    view: *View = undefined,
    scene: *Scene = undefined,

    workers: []Worker = &.{},

    tiles: TileQueue = undefined,

    target: img.Float4 = .{},

    frame: u32 = undefined,

    progressor: progress.StdOut = undefined,

    pub fn init(alloc: *Allocator, threads: *Threads) !Driver {
        const workers = try alloc.alloc(Worker, threads.numThreads());
        for (workers) |*w| {
            w.* = try Worker.init(alloc);
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
        const volumes = view.volumes orelse return Error.InvalidVolumeIntegrator;

        self.view = view;
        self.scene = scene;

        const camera = &self.view.camera;

        const dim = camera.sensorDimensions();

        try camera.sensor.resize(alloc, dim);

        for (self.workers) |*w| {
            try w.configure(alloc, camera, scene, view.num_samples_per_pixel, view.samplers, surfaces, volumes);
        }

        self.tiles.configure(camera.crop, 32, 0);

        try self.target.resize(alloc, img.Description.init2D(dim));
    }

    pub fn render(self: *Driver, alloc: *Allocator, frame: u32) !void {
        if (0 == self.view.num_samples_per_pixel) {
            return;
        }

        std.debug.print("Frame {}\n", .{frame});

        const render_start = std.time.milliTimestamp();

        var camera = &self.view.camera;

        const camera_pos = self.scene.propWorldPosition(camera.entity);

        const start = @as(u64, frame) * camera.frame_step;

        try self.scene.simulate(
            alloc,
            camera_pos,
            start,
            start + camera.frame_duration,
            self.workers[0].super,
            self.threads,
        );

        camera.update(start, &self.workers[0].super);

        std.debug.print("Preparation time {d:.3} s\n", .{chrono.secondsSince(render_start)});

        std.debug.print("Tracing camera rays...\n", .{});

        const camera_start = std.time.milliTimestamp();

        camera.sensor.clear(0.0);

        self.progressor.start(self.tiles.size());

        self.tiles.restart();
        self.frame = frame;

        self.threads.runParallel(self, renderTiles, 0);

        std.debug.print("Camera ray time {d:.3} s\n", .{chrono.secondsSince(camera_start)});

        std.debug.print("Render time {d:.3} s\n", .{chrono.secondsSince(render_start)});

        const pp_start = std.time.milliTimestamp();

        const resolution = camera.resolution;
        const total_crop = Vec4i{ 0, 0, resolution[0], resolution[1] };
        if (@reduce(.Or, total_crop != camera.crop)) {
            camera.sensor.fixZeroWeights();
        }

        self.view.pipeline.apply(camera.sensor, &self.target, self.threads);

        std.debug.print("Post-process time {d:.3} s\n", .{chrono.secondsSince(pp_start)});
    }

    pub fn exportFrame(self: *Driver) void {
        _ = self;
        //self.view.camera.sensor.resolve(&self.target);
    }

    fn renderTiles(context: ThreadContext, id: u32) void {
        const self = @intToPtr(*Driver, context);

        const num_samples = self.view.num_samples_per_pixel;

        while (self.tiles.pop()) |tile| {
            self.workers[id].render(self.frame, tile, num_samples);

            self.progressor.tick();
        }
    }
};
