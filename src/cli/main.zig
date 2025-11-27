const Options = @import("options.zig").Options;
const TakeLoader = @import("take_loader.zig");

const util = @import("util");
const Graph = util.SceneGraph;
const SceneLoader = util.SceneLoader;

const core = @import("core");
const log = core.log;
const rendering = core.rendering;
const Resources = core.resource.Manager;
const scn = core.scene;

const base = @import("base");
const chrono = base.chrono;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn main() !void {
    // core.size_test.testSize();

    log.info("Welcome to zyg!", .{});

    // var da: std.heap.DebugAllocator(.{}) = .init;
    // defer _ = da.deinit();

    // const alloc = da.allocator();
    const alloc = std.heap.c_allocator;

    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    var args = try std.process.argsWithAllocator(alloc);
    var options = try Options.parse(alloc, args);
    args.deinit();
    defer options.deinit(alloc);

    if (0 == options.take.len) {
        log.err("No take specified", .{});
        return;
    }

    const num_workers = Threads.availableCores(options.threads);

    log.info("#Threads {}", .{num_workers});

    var threads: Threads = .{};
    try threads.configure(alloc, num_workers);
    defer threads.deinit(alloc);

    // try core.ggx_integrate.integrate(alloc, &threads);
    // try core.rainbow_integrate.integrate(alloc);
    // try core.image.testing.write_reference_normal_map(alloc, "reference_normal.png");

    var resources = try Resources.init(alloc, io, &threads);
    defer resources.deinit(alloc);

    resources.materials.provider.setSettings(options.no_tex, options.no_tex_dwim, options.debug_material);

    var graph = try Graph.init(alloc, &resources);
    defer graph.deinit(alloc);

    var fs = &resources.fs;

    if (0 == options.mounts.items.len) {
        try fs.pushMount(alloc, "../data");
    } else {
        for (options.mounts.items) |i| {
            try fs.pushMount(alloc, i);
        }
    }

    var scene_loader = SceneLoader.init(alloc, &resources, Resources.MaterialProvider.createFallbackMaterial());
    defer scene_loader.deinit(alloc);

    var driver = try rendering.Driver.init(alloc, &threads, .{ .StdOut = undefined });
    defer driver.deinit(alloc);

    // graph.clear(alloc, true);

    log.info("Loading...", .{});

    const loading_start = chrono.now(io);

    if (try loadTakeAndScene(
        alloc,
        options.take,
        options.start_frame,
        &graph,
        &scene_loader,
        &resources,
    )) {
        log.info("Loading time {d:.2} s", .{chrono.secondsSince(io, loading_start)});

        log.info("Rendering...", .{});

        const rendering_start = chrono.now(io);

        try driver.configure(alloc, &graph.take.view, &graph.scene);

        var i = options.start_frame;
        const end = i + options.num_frames;
        while (i < end) : (i += 1) {
            reloadFrameDependant(
                alloc,
                io,
                i,
                &graph,
                &scene_loader,
                &resources,
            ) catch continue;

            for (graph.take.view.cameras.items, 0..) |*camera, cid| {
                const start = @as(u64, i) * camera.super().frame_step;
                graph.simulate(start, start + camera.super().frame_duration);

                const camera_id: u32 = @intCast(cid);
                try driver.render(alloc, io, camera_id, i, options.sample, options.num_samples);
                try driver.exportFrame(alloc, io, camera_id, i, graph.take.exporters.items);
            }
        }

        log.info("Total render time {d:.2} s", .{chrono.secondsSince(io, rendering_start)});

        if (options.stats) {
            try printStats(&graph.scene);
        }
    }
}

fn loadTakeAndScene(
    alloc: Allocator,
    take_text: []const u8,
    frame: u32,
    graph: *Graph,
    scene_loader: *SceneLoader,
    resources: *Resources,
) !bool {
    resources.fs.frame = frame;

    var stream = resources.fs.readStream(alloc, take_text) catch |err| {
        log.err("Open stream \"{s}\": {}", .{ take_text, err });
        return false;
    };

    graph.take.resolved_filename = try resources.fs.cloneLastResolvedName(alloc);

    TakeLoader.load(alloc, stream, graph, resources) catch |err| {
        log.err("Loading take: {}", .{err});
        return false;
    };

    stream.deinit();

    resources.setFrameTime(frame, graph.take.view.cameras.items[0].super().*);

    scene_loader.load(alloc, graph) catch |err| {
        log.err("Loading scene: {}", .{err});
        return false;
    };

    return true;
}

fn reloadFrameDependant(
    alloc: Allocator,
    io: Io,
    frame: u32,
    graph: *Graph,
    scene_loader: *SceneLoader,
    resources: *Resources,
) !void {
    var fs = &resources.fs;

    if (frame == fs.frame) {
        return;
    }

    fs.frame = frame;
    resources.setFrameTime(frame, graph.take.view.cameras.items[0].super().*);

    if (!try resources.reloadFrameDependant(alloc)) {
        return;
    }

    log.info("Loading...", .{});

    const loading_start = chrono.now(io);

    try resources.commitMaterials(alloc);
    graph.clear(alloc, false);

    // This is a hack to recreate the camera entities that come from the take file in the scene.
    // It relies on the specifiec order in which they are loaded and I hate everything that has to do with it.
    // This whole weird frame depenendant mechanism should be replaced with something more robust!
    const num_take_cameras = graph.camera_trafos.items.len;
    for (graph.take.view.cameras.items[0..num_take_cameras], graph.camera_trafos.items) |*camera, trafo| {
        const entity_id = try graph.scene.createEntity(alloc);
        var camera_base = camera.super();
        camera_base.entity = entity_id;
        graph.scene.prop_space.setWorldTransformation(entity_id, trafo);
        graph.scene.calculateNumInterpolationFrames(camera_base.frame_step, camera_base.frame_duration);
    }

    scene_loader.load(alloc, graph) catch |err| {
        log.err("Loading scene: {}", .{err});
        return err;
    };

    log.info("Loading time {d:.2} s", .{chrono.secondsSince(io, loading_start)});
}

fn printStats(scene: *const scn.Scene) !void {
    std.debug.print("Statistics\n", .{});
    std.debug.print("#props:     {}\n", .{scene.props.items.len});

    {
        var num_bytes: usize = 0;
        for (scene.samplers.resources.items) |*s| {
            num_bytes += s.impl.estimateNumBytes();
        }

        num_bytes += scene.light_distribution.numBytes();
        num_bytes += scene.light_tree.estimateNumBytes();

        var bytes_buf: [32]u8 = undefined;
        const bytes_str = try formatBytes(num_bytes, &bytes_buf);

        std.debug.print("#lights:    {}\t{s}\n", .{ scene.lights.items.len, bytes_str });
    }

    std.debug.print("#shapes:    {}\n", .{scene.resources.shapes.resources.items.len});
    std.debug.print("#materials: {}\n", .{scene.resources.materials.resources.items.len});

    {
        var num_bytes: usize = 0;
        for (scene.resources.images.resources.items) |i| {
            num_bytes += i.estimateNumBytes();
        }

        var bytes_buf: [32]u8 = undefined;
        const bytes_str = try formatBytes(num_bytes, &bytes_buf);

        std.debug.print("#images:    {}\t{s}\n", .{ scene.resources.images.resources.items.len, bytes_str });
    }
}

fn formatBytes(num_bytes: usize, buffer: []u8) ![]u8 {
    if (num_bytes < 1024) {
        return try std.fmt.bufPrint(buffer, "{d} Bytes", .{num_bytes});
    }

    const fnum_bytes: f64 = @floatFromInt(num_bytes);

    if (num_bytes < 1024 * 1024) {
        return try std.fmt.bufPrint(buffer, "{d:4.0} KiB", .{fnum_bytes / 1024});
    }

    if (num_bytes < 1024 * 1024 * 1024) {
        return try std.fmt.bufPrint(buffer, "{d:4.1} MiB", .{fnum_bytes / (1024 * 1024)});
    }

    if (num_bytes < 1024 * 1024 * 1024 * 1024) {
        return try std.fmt.bufPrint(buffer, "{d:4.2} GiB", .{fnum_bytes / (1024 * 1024 * 1024)});
    }

    return try std.fmt.bufPrint(buffer, "{d:5.3} TiB", .{fnum_bytes / (1024 * 1024 * 1024 * 1024)});
}
