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
const PngWriter = @import("../image/encoding/png/png_writer.zig").Writer;
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
    layer_id: u32 = undefined,
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
                &view.surface_integrator,
                &view.lighttracer,
                view.samplers,
                view.aovs,
                view.photon_settings,
                if (self.photon_map.num_paths > 0) &self.photon_map else null,
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

        const dim = camera.resolution;

        const view = self.view;

        try view.sensor.resize(alloc, dim, camera.numLayers(), view.aovs, view.aov_noise);

        self.tiles.configure(camera.resolution, camera.crop, Worker.Tile_dimensions);

        try self.target.resize(alloc, img.Description.init2D(dim));

        const num_particles = @as(u64, @intCast(dim[0] * dim[1])) * @as(u64, view.num_particles_per_pixel);
        self.ranges.configure(num_particles, 0, Num_particles_per_chunk);

        try self.startFrame(alloc, camera_id, frame, false);

        self.frame_iteration = iteration;
        self.frame_iteration_samples = if (num_samples > 0) num_samples else view.num_samples_per_pixel;

        log.info("Preparation time {d:.3} s", .{chrono.secondsSince(render_start)});

        self.bakePhotons(alloc);

        self.renderFrameBackward(camera_id);
        self.renderFrameForward(camera_id);

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

        for (self.workers) |*w| {
            w.camera = camera;
        }

        if (progressive) {
            for (0..camera.numLayers()) |l| {
                self.view.sensor.layers[l].buffer.clear(0.0);
            }
        }
    }

    pub fn renderIterations(self: *Driver, iteration: u32, num_samples: u32) void {
        self.frame_iteration = iteration;
        self.frame_iteration_samples = num_samples;

        self.renderFrameIterationForward();
    }

    pub fn resolveToBuffer(self: *Driver, camera_id: u32, layer_id: u32, target: [*]Pack4f, num_pixels: u32) void {
        const camera = &self.view.cameras.items[camera_id];
        const resolution = camera.resolution;
        const total_crop = Vec4i{ 0, 0, resolution[0], resolution[1] };
        if (@reduce(.Or, total_crop != camera.crop)) {
            self.view.sensor.layers[layer_id].buffer.fixZeroWeights();
        }

        if (self.ranges.size() > 0 and self.view.num_samples_per_pixel > 0) {
            self.view.sensor.resolveAccumulateTonemap(layer_id, target, num_pixels, self.threads);
        } else {
            self.view.sensor.resolveTonemap(layer_id, target, num_pixels, self.threads);
        }
    }

    pub fn resolve(self: *Driver, camera_id: u32, layer_id: u32) void {
        const num_pixels: u32 = @intCast(self.target.description.numPixels());
        self.resolveToBuffer(camera_id, layer_id, self.target.pixels.ptr, num_pixels);
    }

    pub fn resolveAovToBuffer(self: *Driver, layer_id: u32, class: View.AovValue.Class, target: [*]Pack4f, num_pixels: u32) bool {
        if (!self.view.aovs.activeClass(class)) {
            return false;
        }

        self.view.sensor.resolveAov(layer_id, class, target, num_pixels, self.threads);

        return true;
    }

    pub fn resolveAov(self: *Driver, layer_id: u32, class: View.AovValue.Class) bool {
        const num_pixels: u32 = @intCast(self.target.description.numPixels());
        return self.resolveAovToBuffer(layer_id, class, self.target.pixels.ptr, num_pixels);
    }

    pub fn exportFrame(self: *Driver, alloc: Allocator, camera_id: u32, frame: u32, exporters: []Sink) !void {
        const start = std.time.milliTimestamp();

        const camera = &self.view.cameras.items[camera_id];
        const crop = camera.crop;

        for (0..camera.numLayers()) |l| {
            const layer_id: u32 = @truncate(l);

            self.resolve(camera_id, layer_id);

            for (exporters) |*e| {
                try e.write(alloc, self.target, crop, null, camera, camera_id, layer_id, frame, self.threads);
            }

            for (0..View.AovValue.NumClasses) |i| {
                const class: View.AovValue.Class = @enumFromInt(i);
                if (!self.resolveAov(layer_id, class)) {
                    continue;
                }

                for (exporters) |*e| {
                    try e.write(alloc, self.target, crop, class, camera, camera_id, layer_id, frame, self.threads);
                }
            }

            if (self.view.aov_sample_count) {
                const d = camera.resolution;
                const weights = try alloc.alloc(f32, @as(u32, @intCast(d[0] * d[1])));
                defer alloc.free(weights);

                self.view.sensor.layers[layer_id].buffer.copyWeights(weights);

                var min: f32 = std.math.floatMax(f32);
                var max: f32 = 0.0;

                for (weights) |w| {
                    if (w > 0.0) {
                        min = math.min(min, w);
                    }
                    max = math.max(max, w);
                }

                var buf: [32]u8 = undefined;
                const filename = try std.fmt.bufPrint(&buf, "image_{d:0>2}_{d:0>6}{s}_sc.png", .{ camera_id, frame, camera.layerExtension(layer_id) });

                try PngWriter.writeHeatmap(alloc, d[0], d[1], weights, min, max, filename);

                log.info("Sample count [{}, {}]", .{ @as(u32, @intFromFloat(@ceil(min))), @as(u32, @intFromFloat(@ceil(max))) });
            }

            if (self.view.aov_noise) {
                const d = camera.resolution;

                var min: f32 = std.math.floatMax(f32);
                var max: f32 = 0.0;

                for (self.view.sensor.layers[layer_id].aov_noise_buffer) |w| {
                    if (w > 0.0) {
                        min = math.min(min, w);
                    }
                    max = math.max(max, w);
                }

                var buf: [32]u8 = undefined;
                const filename = try std.fmt.bufPrint(&buf, "image_{d:0>2}_{d:0>6}{s}_noise.png", .{ camera_id, frame, camera.layerExtension(layer_id) });

                try PngWriter.writeHeatmap(alloc, d[0], d[1], self.view.sensor.layers[layer_id].aov_noise_buffer, min, max, filename);

                log.info("Noise [{}, {}]", .{ min, max });
            }
        }

        log.info("Export time {d:.3} s", .{chrono.secondsSince(start)});
    }

    fn renderFrameBackward(self: *Driver, camera_id: u32) void {
        if (0 == self.ranges.size()) {
            return;
        }

        log.info("Tracing light rays...", .{});

        const start = std.time.milliTimestamp();

        const camera = &self.view.cameras.items[camera_id];
        var sensor = &self.view.sensor;

        const num_layers = camera.numLayers();

        const ppp: f32 = @floatFromInt(self.view.num_particles_per_pixel);

        for (0..num_layers) |l| {
            sensor.layers[l].buffer.clear(ppp);
        }

        self.progressor.start(self.ranges.size());

        self.ranges.restart(0);

        self.threads.runParallel(self, renderRanges, 0);

        // If there will be a forward pass later...
        if (self.view.num_samples_per_pixel > 0) {
            const num_pixels: u32 = @intCast(self.target.description.numPixels());

            for (0..num_layers) |l| {
                sensor.resolve(@truncate(l), self.target.pixels.ptr, num_pixels, self.threads);
            }
        }

        log.info("Light ray time {d:.3} s", .{chrono.secondsSince(start)});
    }

    fn renderTiles(context: Threads.Context, id: u32) void {
        const self: *Driver = @ptrCast(@alignCast(context));

        const iteration = self.frame_iteration;
        const num_samples = self.frame_iteration_samples;
        const num_expected_samples = self.view.num_samples_per_pixel;
        const qm_threshold = self.view.qm_threshold;

        self.workers[id].layer = self.layer_id;

        while (self.tiles.pop()) |tile| {
            self.workers[id].render(self.frame, tile, iteration, num_samples, num_expected_samples, qm_threshold);

            self.progressor.tick();
        }
    }

    fn renderFrameForward(self: *Driver, camera_id: u32) void {
        if (0 == self.view.num_samples_per_pixel) {
            return;
        }

        log.info("Tracing camera rays...", .{});
        const start = std.time.milliTimestamp();

        const camera = &self.view.cameras.items[camera_id];
        var sensor = &self.view.sensor;

        const num_layers = camera.numLayers();

        self.progressor.start(self.tiles.size() * num_layers);

        for (0..num_layers) |l| {
            self.layer_id = @truncate(l);

            sensor.layers[l].buffer.clear(0.0);
            sensor.layers[l].aov.clear();
            sensor.layers[l].clearNoiseAov();

            self.tiles.restart();

            self.threads.runParallel(self, renderTiles, 0);
        }

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
        const self: *Driver = @ptrCast(@alignCast(context));

        // Just pick one layer for now
        // It should just be used for differential estimation...
        self.workers[id].layer = 0;

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

        //   const iteration_threshold = self.view.photon_settings.iteration_threshold;

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

            // if (0 == new_begin or num_photons == new_begin or 1.0 <= iteration_threshold or
            //     @as(f32, @floatFromInt(begin)) / @as(f32, @floatFromInt(new_begin)) > (1.0 - iteration_threshold))
            // {
            //     break;
            // }

            begin = new_begin;

            break;
        }

        self.photon_map.compileFinalize();

        log.info("Photon time {d:.3} s", .{chrono.secondsSince(start)});
    }

    fn bakeRanges(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        const self: *Driver = @ptrCast(@alignCast(context));

        self.photon_infos[id].num_paths = self.workers[id].bakePhotons(
            begin,
            end,
            self.frame,
            self.frame_iteration,
        );
    }
};
