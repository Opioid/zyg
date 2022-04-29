const Options = @import("options.zig").Options;
const Graph = @import("scene_graph.zig").Graph;
const SceneLoader = @import("scene_loader.zig").Loader;
const TakeLoader = @import("take_loader.zig");

const core = @import("core");
const log = core.log;
const rendering = core.rendering;
const resource = core.resource;
const scn = core.scn;
const tk = core.tk;

const base = @import("base");
const chrono = base.chrono;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("any_key.h");
});

pub fn main() !void {
    // core.size_test.testSize();

    log.info("Welcome to zyg!", .{});

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer {
    //     const leaked = gpa.deinit();
    //     if (leaked) {
    //         log.warning("Memory leak {}", .{leaked});
    //     }
    // }

    // const alloc = gpa.allocator();
    const alloc = std.heap.c_allocator;

    var options = try Options.parse(alloc, std.process.args());
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

    var graph = try Graph.init(alloc);
    defer graph.deinit(alloc);

    var resources = try resource.Manager.init(alloc, &graph.scene, &threads);
    defer resources.deinit(alloc);

    resources.materials.provider.setSettings(options.no_tex, options.no_tex_dwim, options.debug_material);

    var fs = &resources.fs;

    if (0 == options.mounts.items.len) {
        try fs.pushMount(alloc, "../data");
    } else {
        for (options.mounts.items) |i| {
            try fs.pushMount(alloc, i);
        }
    }

    var scene_loader = SceneLoader.init(alloc, &resources, resource.MaterialProvider.createFallbackMaterial());
    defer scene_loader.deinit(alloc);

    var take = tk.Take{};
    defer take.deinit(alloc);

    var driver = try rendering.Driver.init(alloc, &threads, .{ .StdOut = .{} });
    defer driver.deinit(alloc);

    while (true) {
        take.clear(alloc);
        graph.clear(alloc);

        log.info("Loading...", .{});

        const loading_start = std.time.milliTimestamp();

        if (loadTakeAndScene(
            alloc,
            options.take,
            options.start_frame,
            &take,
            &graph,
            &scene_loader,
            &resources,
        )) {
            log.info("Loading time {d:.2} s", .{chrono.secondsSince(loading_start)});
            log.info("Rendering...", .{});

            const rendering_start = std.time.milliTimestamp();

            try driver.configure(alloc, &take.view, &graph.scene);

            var i = options.start_frame;
            const end = i + options.num_frames;
            while (i < end) : (i += 1) {
                reloadFrameDependant(
                    alloc,
                    i,
                    options.take,
                    &take,
                    &graph,
                    &scene_loader,
                    &resources,
                ) catch continue;

                const camera = take.view.camera;
                const start = @as(u64, i) * camera.frame_step;
                graph.simulate(start, start + camera.frame_duration);

                try driver.render(alloc, i);
                try driver.exportFrame(alloc, i, take.exporters.items);
            }

            log.info("Total render time {d:.2} s", .{chrono.secondsSince(rendering_start)});
        }

        if (options.iter) {
            std.debug.print("Press 'q' to quit, or any other key to render again.\n", .{});
            const key = c.read_key();
            if ('q' != key) {
                continue;
            }
        }

        break;
    }
}

fn loadTakeAndScene(
    alloc: Allocator,
    take_text: []const u8,
    frame: u32,
    take: *tk.Take,
    graph: *Graph,
    scene_loader: *SceneLoader,
    resources: *resource.Manager,
) bool {
    resources.fs.frame = frame;

    var stream = resources.fs.readStream(alloc, take_text) catch |err| {
        log.err("Open stream \"{s}\": {}", .{ take_text, err });
        return false;
    };

    TakeLoader.load(alloc, stream, take, &graph.scene) catch |err| {
        log.err("Loading take: {}", .{err});
        return false;
    };

    stream.deinit();

    scene_loader.load(alloc, take.scene_filename, take.*, graph) catch |err| {
        log.err("Loading scene: {}", .{err});
        return false;
    };

    return true;
}

fn reloadFrameDependant(
    alloc: Allocator,
    frame: u32,
    take_text: []const u8,
    take: *tk.Take,
    graph: *Graph,
    scene_loader: *SceneLoader,
    resources: *resource.Manager,
) !void {
    var fs = &resources.fs;

    if (frame == fs.frame) {
        return;
    }

    fs.frame = frame;

    if (!try resources.images.reloadFrameDependant(alloc, resources)) {
        return;
    }

    log.info("Loading...", .{});

    const loading_start = std.time.milliTimestamp();

    try graph.scene.commitMaterials(alloc, resources.threads);
    graph.clear(alloc);

    var stream = resources.fs.readStream(alloc, take_text) catch |err| {
        log.err("Open stream \"{s}\": {}", .{ take_text, err });
        return err;
    };

    TakeLoader.loadCameraTransformation(alloc, stream, &take.view.camera, &graph.scene) catch |err| {
        log.err("Loading take: {}", .{err});
        return err;
    };

    stream.deinit();

    scene_loader.load(alloc, take.scene_filename, take.*, graph) catch |err| {
        log.err("Loading scene: {}", .{err});
        return err;
    };

    log.info("Loading time {d:.2} s", .{chrono.secondsSince(loading_start)});
}
