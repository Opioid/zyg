const log = @import("../log.zig");
const View = @import("../take/take.zig").View;
const Sink = @import("../exporting/sink.zig").Sink;
const Scene = @import("../scene/scene.zig").Scene;
const Worker = @import("worker.zig").Worker;
const tq = @import("tile_queue.zig");
const TileQueue = tq.TileQueue;
const RangeQueue = tq.RangeQueue;
const img = @import("../image/image.zig");
const PhotonMap = @import("integrator/particle/photon/photon_map.zig").Map;
const progress = @import("../progress.zig");
const PngWriter = @import("../image/encoding/png/writer.zig").Writer;

const base = @import("base");
const chrono = base.chrono;
const Threads = base.thread.Pool;
const math = base.math;
const Vec4i = math.Vec4i;

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const Error = error{
    InvalidSurfaceIntegrator,
    InvalidVolumeIntegrator,
    InvalidLighttracer,
};

const Num_particles_per_chunk = 1024;

pub const Driver = struct {
    const PhotonInfo = struct {
        num_paths: u32,
    };

    threads: *Threads,

    view: *View = undefined,
    scene: *Scene = undefined,

    workers: []Worker,
    photon_infos: []PhotonInfo,

    tiles: TileQueue = undefined,
    ranges: RangeQueue = undefined,

    target: img.Float4 = .{},

    photon_map: PhotonMap = .{},

    min_samples: u32 = 0,
    max_samples: u32 = 0,
    frame: u32 = 0,
    frame_iteration: u32 = 0,

    progressor: progress.StdOut = undefined,

    pub fn init(alloc: Allocator, threads: *Threads) !Driver {
        const workers = try alloc.alloc(Worker, threads.numThreads());
        for (workers) |*w| {
            w.* = try Worker.init(alloc);
        }

        return Driver{
            .threads = threads,
            .workers = workers,
            .photon_infos = try alloc.alloc(PhotonInfo, threads.numThreads()),
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
        const surfaces = view.surfaces orelse return Error.InvalidSurfaceIntegrator;
        const volumes = view.volumes orelse return Error.InvalidVolumeIntegrator;
        const lighttracers = view.lighttracers orelse return Error.InvalidLighttracer;

        self.view = view;
        self.scene = scene;

        const max_samples = view.num_samples_per_pixel;
        self.min_samples = @floatToInt(u32, @ceil(@sqrt(@intToFloat(f32, 16 * max_samples))));
        self.max_samples = max_samples;

        const camera = &self.view.camera;
        const dim = camera.sensorDimensions();
        try camera.sensor.resize(alloc, dim);

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
                camera,
                scene,
                max_samples,
                view.samplers,
                surfaces,
                volumes,
                lighttracers,
                view.photon_settings,
                &self.photon_map,
            );
        }

        self.tiles.configure(camera.crop, 16);

        try self.target.resize(alloc, img.Description.init2D(dim));

        const r = camera.resolution;
        const num_particles = @intCast(u64, r[0] * r[1]) * @as(u64, view.num_particles_per_pixel);
        self.ranges.configure(num_particles, 0, Num_particles_per_chunk);
    }

    pub fn render(self: *Driver, alloc: Allocator, frame: u32) !void {
        log.info("Frame {}", .{frame});

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

        log.info("Preparation time {d:.3} s", .{chrono.secondsSince(render_start)});

        self.bakePhotons(alloc, frame);
        self.renderFrameBackward(frame);
        self.renderFrameForward(frame);

        log.info("Render time {d:.3} s", .{chrono.secondsSince(render_start)});

        const pp_start = std.time.milliTimestamp();

        const resolution = camera.resolution;
        const total_crop = Vec4i{ 0, 0, resolution[0], resolution[1] };
        if (@reduce(.Or, total_crop != camera.crop)) {
            camera.sensor.fixZeroWeights();
        }

        self.postprocess();

        log.info("Post-process time {d:.3} s", .{chrono.secondsSince(pp_start)});
    }

    pub fn exportFrame(self: Driver, alloc: Allocator, frame: u32, exporters: []Sink) !void {
        const start = std.time.milliTimestamp();

        for (exporters) |*e| {
            try e.write(alloc, self.target, frame, self.threads);
        }

        log.info("Export time {d:.3} s", .{chrono.secondsSince(start)});

        const d = self.view.camera.sensorDimensions();
        var sensor = self.view.camera.sensor;

        var weights = try alloc.alloc(f32, @intCast(u32, d[0] * d[1]));
        defer alloc.free(weights);

        sensor.copyWeights(weights);

        var min: f32 = std.math.f32_max;
        var max: f32 = 0.0;

        for (weights) |w| {
            min = @minimum(min, w);
            max = @maximum(max, w);
        }

        try PngWriter.writeHeatmap(alloc, d[0], d[1], weights, min, max, "info_sample_count.png");

        const ee = sensor.base().ee;

        min = std.math.f32_max;
        max = 0.0;

        for (ee) |s| {
            min = @minimum(min, s);
            max = @maximum(max, s);

            //  std.debug.print("{}\n", .{s});
        }

        try PngWriter.writeHeatmap(alloc, d[0], d[1], ee, min, max, "info_error_estimate.png");

        const dee = sensor.base().dee;

        min = std.math.f32_max;
        max = 0.0;

        for (dee) |s| {
            min = @minimum(min, s);
            max = @maximum(max, s);

            //  std.debug.print("{}\n", .{s});
        }

        try PngWriter.writeHeatmap(alloc, d[0], d[1], dee, min, max, "info_diluted_error_estimate.png");
    }

    fn renderFrameBackward(self: *Driver, frame: u32) void {
        if (0 == self.ranges.size()) {
            return;
        }

        log.info("Tracing light rays...", .{});

        const start = std.time.milliTimestamp();

        var camera = &self.view.camera;

        camera.sensor.clear(@intToFloat(f32, self.view.numParticleSamplesPerPixel()));

        self.progressor.start(self.ranges.size());

        self.ranges.restart(0);
        self.frame = frame;

        self.threads.runParallel(self, renderRanges, 0);

        // If there will be a forward pass later...
        if (self.view.num_samples_per_pixel > 0) {
            self.view.pipeline.seed(camera.sensor, &self.target, self.threads);
        }

        log.info("Light ray time {d:.3} s", .{chrono.secondsSince(start)});
    }

    fn renderTilesTrackVariance(context: Threads.Context, id: u32) void {
        const self = @intToPtr(*Driver, context);

        while (self.tiles.pop()) |tile| {
            self.workers[id].renderTrackVariance(self.frame, tile, self.min_samples);

            self.progressor.tick();
        }
    }

    fn renderTilesRemainder(context: Threads.Context, id: u32) void {
        const self = @intToPtr(*Driver, context);

        const target_cv = self.view.cv;

        while (self.tiles.pop()) |tile| {
            self.workers[id].renderRemainder(self.frame, tile, self.min_samples, self.max_samples, target_cv);

            self.progressor.tick();
        }
    }

    fn renderFrameForward(self: *Driver, frame: u32) void {
        if (0 == self.view.num_samples_per_pixel) {
            return;
        }

        log.info("Tracing camera rays...", .{});
        const start = std.time.milliTimestamp();

        var camera = &self.view.camera;

        camera.sensor.clear(0.0);

        self.progressor.start(self.tiles.size() * 2);

        self.frame = frame;

        self.tiles.restart();
        self.threads.runParallel(self, renderTilesTrackVariance, 0);

        camera.sensor.base().diluteErrorEstimate(self.threads);

        self.tiles.restart();
        self.threads.runParallel(self, renderTilesRemainder, 0);

        log.info("Camera ray time {d:.3} s", .{chrono.secondsSince(start)});
    }

    fn renderRanges(context: Threads.Context, id: u32) void {
        const self = @intToPtr(*Driver, context);

        while (self.ranges.pop()) |range| {
            self.workers[id].particles(self.frame, 0, range);

            self.progressor.tick();
        }
    }

    fn bakePhotons(self: *Driver, alloc: Allocator, frame: u32) void {
        const num_photons = self.view.photon_settings.num_photons;

        if (0 == num_photons) {
            return;
        }

        log.info("Baking photons...", .{});
        const start = std.time.milliTimestamp();

        for (self.workers) |*w, i| {
            w.super.rng.start(0, i);
        }

        var num_paths: u64 = 0;
        var begin: u32 = 0;

        const iteration_threshold = self.view.photon_settings.iteration_threshold;

        self.photon_map.start();

        self.frame = frame;

        var iteration: u32 = 0;

        while (true) : (iteration += 1) {
            self.frame_iteration = iteration;

            const num = self.threads.runRange(self, bakeRanges, begin, num_photons);

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
                @intToFloat(f32, begin) / @intToFloat(f32, new_begin) > (1.0 - iteration_threshold))
            {
                break;
            }

            begin = new_begin;
        }

        self.photon_map.compileFinalize();

        log.info("Photon time {d:.3} s", .{chrono.secondsSince(start)});
    }

    fn bakeRanges(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        const self = @intToPtr(*Driver, context);

        self.photon_infos[id].num_paths = self.workers[id].bakePhotons(
            begin,
            end,
            self.frame,
            self.frame_iteration,
        );
    }

    fn postprocess(self: *Driver) void {
        var camera = &self.view.camera;

        if (self.ranges.size() > 0 and self.view.num_samples_per_pixel > 0) {
            self.view.pipeline.applyAccumulate(camera.sensor, &self.target, self.threads);
        } else {
            self.view.pipeline.apply(camera.sensor, &self.target, self.threads);
        }
    }
};
