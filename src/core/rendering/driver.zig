const log = @import("../log.zig");
const Filesystem = @import("../file/system.zig").System;
const View = @import("../take/take.zig").View;
const Sink = @import("../exporting/sink.zig").Sink;
const Scene = @import("../scene/scene.zig").Scene;
const Worker = @import("worker.zig").Worker;
const tq = @import("tile_queue.zig");
const TileQueue = tq.TileQueue;
const RangeQueue = tq.RangeQueue;
const img = @import("../image/image.zig");
const PhotonMap = @import("integrator/particle/photon/photon_map.zig").Map;
const Progressor = @import("../progress.zig").Progressor;
pub const snsr = @import("sensor/sensor.zig");

const base = @import("base");
const chrono = base.chrono;
const Threads = base.thread.Pool;
const math = base.math;
const Vec4i = math.Vec4i;
const Pack4f = math.Pack4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Num_particles_per_chunk = 1024;

const Error = error{
    NoCameraProp,
};

pub const Driver = struct {
    const PhotonInfo = struct {
        num_paths: u32,
    };

    threads: *Threads,
    fs: *Filesystem,

    view: *View = undefined,
    scene: *Scene = undefined,

    workers: []Worker,
    photon_infos: []PhotonInfo,

    tiles: TileQueue = undefined,
    ranges: RangeQueue = undefined,

    target: img.Float4 = .{},

    photon_map: PhotonMap = .{},

    camera_id: u32 = undefined,
    frame: u32 = undefined,
    frame_iteration: u32 = undefined,
    frame_iteration_samples: u32 = undefined,

    progressor: Progressor,

    pub fn init(alloc: Allocator, threads: *Threads, fs: *Filesystem, progressor: Progressor) !Driver {
        const workers = try alloc.alloc(Worker, threads.numThreads());
        @memset(workers, .{});

        return Driver{
            .threads = threads,
            .fs = fs,
            .workers = workers,
            .photon_infos = try alloc.alloc(PhotonInfo, threads.numThreads()),
            .progressor = progressor,
        };
    }

    pub fn deinit(self: *Driver, alloc: Allocator) void {
        self.target.deinit(alloc);

        alloc.free(self.photon_infos);

        for (self.workers) |*w| {
            w.deinit(alloc);
        }

        alloc.free(self.workers);

        self.photon_map.deinit(alloc);
    }

    pub fn configure(self: *Driver, alloc: Allocator, view: *View, scene: *Scene) !void {
        self.view = view;
        self.scene = scene;

        const num_photons = view.photon_settings.num_photons;
        if (num_photons > 0) {
            try self.photon_map.configure(
                alloc,
                self.threads.numThreads(),
                num_photons,
                view.photon_settings.search_radius,
            );
        }

        for (self.workers) |*w| {
            try w.configure(
                alloc,
                &view.sensor,
                scene,
                view.samplers,
                view.surfaces,
                view.lighttracers,
                view.aovs,
                view.photon_settings,
                &self.photon_map,
            );
        }
    }

    pub fn render(self: *Driver, alloc: Allocator, camera_id: u32, frame: u32, iteration: u32, num_samples: u32) !void {
        log.info("Camera {} Frame {}", .{ camera_id, frame });

        const render_start = std.time.milliTimestamp();

        const camera = &self.view.cameras.items[camera_id];

        if (Scene.Null == camera.entity) {
            return Error.NoCameraProp;
        }

        const dim = camera.sensorDimensions();

        const view = self.view;

        try view.sensor.resize(alloc, dim, view.aovs);

        self.tiles.configure(camera.crop, 32, view.sensor.filter_radius_int);

        try self.target.resize(alloc, img.Description.init2D(dim));

        const r = camera.resolution;
        const num_particles = @as(u64, @intCast(r[0] * r[1])) * @as(u64, view.num_particles_per_pixel);
        self.ranges.configure(num_particles, 0, Num_particles_per_chunk);

        try self.startFrame(alloc, camera_id, frame, false);

        self.frame_iteration = iteration;
        self.frame_iteration_samples = if (num_samples > 0) num_samples else view.num_samples_per_pixel;

        log.info("Preparation time {d:.3} s", .{chrono.secondsSince(render_start)});

        self.bakePhotons(alloc);

        self.renderFrameBackward();
        self.renderFrameForward();

        log.info("Render time {d:.3} s", .{chrono.secondsSince(render_start)});
    }

    pub fn startFrame(self: *Driver, alloc: Allocator, camera_id: u32, frame: u32, progressive: bool) !void {
        self.camera_id = camera_id;
        self.frame = frame;

        var camera = &self.view.cameras.items[camera_id];

        if (Scene.Null == camera.entity) {
            return Error.NoCameraProp;
        }

        const camera_pos = self.scene.propWorldPosition(camera.entity);
        const start = @as(u64, frame) * camera.frame_step;

        try self.scene.compile(alloc, camera_pos, start, self.threads, self.fs);

        camera.update(start, self.scene);

        if (progressive) {
            self.view.sensor.buffer.clear(0.0);
        }
    }

    pub fn renderIterations(self: *Driver, iteration: u32, num_samples: u32) void {
        self.frame_iteration = iteration;
        self.frame_iteration_samples = num_samples;

        self.renderFrameIterationForward();
    }

    pub fn resolveToBuffer(self: *Driver, camera_id: u32, target: [*]Pack4f, num_pixels: u32) void {
        const camera = &self.view.cameras.items[camera_id];
        const resolution = camera.resolution;
        const total_crop = Vec4i{ 0, 0, resolution[0], resolution[1] };
        if (@reduce(.Or, total_crop != camera.crop)) {
            self.view.sensor.buffer.fixZeroWeights();
        }

        if (self.ranges.size() > 0 and self.view.num_samples_per_pixel > 0) {
            self.view.sensor.resolveAccumulateTonemap(target, num_pixels, self.threads);
        } else {
            self.view.sensor.resolveTonemap(target, num_pixels, self.threads);
        }
    }

    pub fn resolve(self: *Driver, camera_id: u32) void {
        const num_pixels = @as(u32, @intCast(self.target.description.numPixels()));
        self.resolveToBuffer(camera_id, self.target.pixels.ptr, num_pixels);
    }

    pub fn resolveAovToBuffer(self: *Driver, class: View.AovValue.Class, target: [*]Pack4f, num_pixels: u32) bool {
        if (!self.view.aovs.activeClass(class)) {
            return false;
        }

        self.view.sensor.resolveAov(class, target, num_pixels, self.threads);

        return true;
    }

    pub fn resolveAov(self: *Driver, class: View.AovValue.Class) bool {
        const num_pixels: u32 = @intCast(self.target.description.numPixels());
        return self.resolveAovToBuffer(class, self.target.pixels.ptr, num_pixels);
    }

    pub fn exportFrame(self: *Driver, alloc: Allocator, camera_id: u32, frame: u32, exporters: []Sink) !void {
        const start = std.time.milliTimestamp();

        self.resolve(camera_id);

        const crop = self.view.cameras.items[camera_id].crop;

        for (exporters) |*e| {
            try e.write(alloc, self.target, crop, null, camera_id, frame, self.threads);
        }

        for (0..View.AovValue.Num_classes) |i| {
            const class: View.AovValue.Class = @enumFromInt(i);
            if (!self.resolveAov(class)) {
                continue;
            }

            for (exporters) |*e| {
                try e.write(alloc, self.target, crop, class, camera_id, frame, self.threads);
            }
        }

        log.info("Export time {d:.3} s", .{chrono.secondsSince(start)});
    }

    fn renderFrameBackward(self: *Driver) void {
        if (0 == self.ranges.size()) {
            return;
        }

        log.info("Tracing light rays...", .{});

        const start = std.time.milliTimestamp();

        var sensor = &self.view.sensor;

        sensor.buffer.clear(@as(f32, @floatFromInt(self.view.num_particles_per_pixel)));

        self.progressor.start(self.ranges.size());

        self.ranges.restart(0);

        self.threads.runParallel(self, renderRanges, 0);

        // If there will be a forward pass later...
        if (self.view.num_samples_per_pixel > 0) {
            const num_pixels = @as(u32, @intCast(self.target.description.numPixels()));
            sensor.resolve(self.target.pixels.ptr, num_pixels, self.threads);
        }

        log.info("Light ray time {d:.3} s", .{chrono.secondsSince(start)});
    }

    fn renderTiles(context: Threads.Context, id: u32) void {
        const self = @as(*Driver, @ptrCast(@alignCast(context)));

        self.workers[id].camera = &self.view.cameras.items[self.camera_id];

        const iteration = self.frame_iteration;
        const num_samples = self.frame_iteration_samples;
        const num_expected_samples = self.view.num_samples_per_pixel;

        while (self.tiles.pop()) |tile| {
            self.workers[id].render(self.frame, tile, iteration, num_samples, num_expected_samples);

            self.progressor.tick();
        }
    }

    fn renderFrameForward(self: *Driver) void {
        if (0 == self.view.num_samples_per_pixel) {
            return;
        }

        log.info("Tracing camera rays...", .{});
        const start = std.time.milliTimestamp();

        var sensor = &self.view.sensor;

        sensor.buffer.clear(0.0);
        sensor.aov.clear();

        self.progressor.start(self.tiles.size());

        self.tiles.restart();

        self.threads.runParallel(self, renderTiles, 0);

        log.info("Camera ray time {d:.3} s", .{chrono.secondsSince(start)});
    }

    fn renderFrameIterationForward(self: *Driver) void {
        if (0 == self.view.num_samples_per_pixel) {
            return;
        }

        self.progressor.start(self.tiles.size());

        self.tiles.restart();

        self.threads.runParallel(self, renderTiles, 0);
    }

    fn renderRanges(context: Threads.Context, id: u32) void {
        const self = @as(*Driver, @ptrCast(@alignCast(context)));

        self.workers[id].camera = &self.view.cameras.items[self.camera_id];

        while (self.ranges.pop()) |range| {
            self.workers[id].particles(self.frame, @as(u64, range.it), range.range);

            self.progressor.tick();
        }
    }

    fn bakePhotons(self: *Driver, alloc: Allocator) void {
        const num_photons = self.view.photon_settings.num_photons;

        if (0 == num_photons) {
            return;
        }

        log.info("Baking photons...", .{});
        const start = std.time.milliTimestamp();

        for (self.workers, 0..) |*w, i| {
            w.rng.start(0, i);
        }

        var num_paths: u64 = 0;
        var begin: u32 = 0;

        const iteration_threshold = self.view.photon_settings.iteration_threshold;

        self.photon_map.start();

        var iteration: u32 = 0;

        while (true) : (iteration += 1) {
            self.frame_iteration = iteration;

            const num = self.threads.runRange(self, bakeRanges, begin, num_photons, 0);

            for (self.photon_infos[0..num]) |i| {
                num_paths += i.num_paths;
            }

            if (0 == num_paths) {
                log.info("No photons", .{});
                break;
            }

            const new_begin = self.photon_map.compileIteration(
                alloc,
                num_photons,
                num_paths,
                self.threads,
            ) catch break;

            if (0 == new_begin or num_photons == new_begin or 1.0 <= iteration_threshold or
                @as(f32, @floatFromInt(begin)) / @as(f32, @floatFromInt(new_begin)) > (1.0 - iteration_threshold))
            {
                break;
            }

            begin = new_begin;
        }

        self.photon_map.compileFinalize();

        log.info("Photon time {d:.3} s", .{chrono.secondsSince(start)});
    }

    fn bakeRanges(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        const self = @as(*Driver, @ptrCast(@alignCast(context)));

        self.photon_infos[id].num_paths = self.workers[id].bakePhotons(
            begin,
            end,
            self.frame,
            self.frame_iteration,
        );
    }
};
