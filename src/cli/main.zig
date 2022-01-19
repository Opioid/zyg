const Options = @import("options.zig").Options;

const core = @import("core");
const log = core.log;
const rendering = core.rendering;
const resource = core.resource;
const scn = core.scn;
const thread = base.thread;
const tk = core.tk;

const base = @import("base");
const chrono = base.chrono;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    // try core.ggx_integrate.integrate();

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

    if (options.take == null) {
        log.err("No take specified", .{});
        return;
    }

    const num_workers = Threads.availableCores(options.threads);

    log.info("#Threads {}", .{num_workers});

    var threads: Threads = .{};
    try threads.configure(alloc, num_workers);
    defer threads.deinit(alloc);

    var resources = try resource.Manager.init(alloc, &threads);
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

    var scene_loader = scn.Loader.init(alloc, &resources, scn.mat.Provider.createFallbackMaterial());
    defer scene_loader.deinit(alloc);

    var scene = try scn.Scene.init(
        alloc,
        &resources.images.resources,
        &resources.materials.resources,
        &resources.shapes.resources,
        scene_loader.null_shape,
    );
    defer scene.deinit(alloc);

    log.info("Loading...", .{});

    const loading_start = std.time.milliTimestamp();

    var stream = resources.fs.readStream(alloc, options.take.?) catch |err| {
        log.err("Open stream \"{s}\": {}", .{ options.take.?, err });
        return;
    };

    var take = tk.load(alloc, stream, &scene, &resources) catch |err| {
        log.err("Loading take: {}", .{err});
        return;
    };
    defer take.deinit(alloc);

    stream.deinit();

    resources.fs.frame = options.start_frame;

    scene_loader.load(alloc, take.scene_filename, take, &scene) catch |err| {
        log.err("Loading scene: {}", .{err});
        return;
    };

    log.info("Loading time {d:.2} s", .{chrono.secondsSince(loading_start)});

    log.info("Rendering...", .{});

    const rendering_start = std.time.milliTimestamp();

    var driver = try rendering.Driver.init(alloc, &threads);
    defer driver.deinit(alloc);

    try driver.configure(alloc, &take.view, &scene);

    var i = options.start_frame;
    const end = i + options.num_frames;
    while (i < end) : (i += 1) {
        reloadFrameDependant(
            alloc,
            i,
            &take,
            options.take.?,
            &scene,
            &scene_loader,
            &resources,
        ) catch continue;

        try driver.render(alloc, i);
        try driver.exportFrame(alloc, i, take.exporters.items);
    }

    log.info("Total render time {d:.2} s\n", .{chrono.secondsSince(rendering_start)});
}

fn reloadFrameDependant(
    alloc: Allocator,
    frame: u32,
    take: *tk.Take,
    take_text: []const u8,
    scene: *scn.Scene,
    scene_loader: *scn.Loader,
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

    try scene.commitMaterials(alloc, resources.threads);
    scene.clear(alloc);

    var stream = resources.fs.readStream(alloc, take_text) catch |err| {
        log.err("Open stream \"{s}\": {}", .{ take_text, err });
        return err;
    };

    tk.loadCameraTransformation(alloc, stream, &take.view.camera, scene) catch |err| {
        log.err("Loading take: {}", .{err});
        return err;
    };

    stream.deinit();

    scene_loader.load(alloc, take.scene_filename, take.*, scene) catch |err| {
        log.err("Loading scene: {}", .{err});
        return err;
    };

    log.info("Loading time {d:.2} s", .{chrono.secondsSince(loading_start)});
}
