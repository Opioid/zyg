const Options = @import("options/options.zig").Options;

const core = @import("core");
const rendering = core.rendering;
const resource = core.resource;
const scn = core.scn;
const thread = base.thread;
const tk = core.tk;
const PngWriter = core.image.encoding.png.Writer;

const base = @import("base");
const chrono = base.chrono;
const Threads = base.thread.Pool;

const std = @import("std");

pub fn main() !void {
    // try core.ggx_integrate.integrate();

    const stdout = std.io.getStdOut().writer();

    stdout.print("Welcome to zyg!\n", .{}) catch unreachable;

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer {
    //     const leaked = gpa.deinit();
    //     if (leaked) {
    //         std.debug.print("Memory leak {} \n", .{leaked});
    //     }
    // }

    // const alloc = &gpa.allocator;
    const alloc = std.heap.c_allocator;

    var options = try Options.parse(alloc, std.process.args());
    defer options.deinit(alloc);

    if (options.take == null) {
        stdout.print("No take specified\n", .{}) catch unreachable;
        return;
    }

    const num_workers = Threads.availableCores(options.threads);

    stdout.print("#Threads {}\n", .{num_workers}) catch unreachable;

    var threads: Threads = .{};
    try threads.configure(alloc, num_workers);
    defer threads.deinit(alloc);

    var resources = resource.Manager.init(&threads);
    defer resources.deinit(alloc);

    resources.materials.provider.setSettings(options.no_tex);

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

    var stream = try resources.fs.readStream(options.take.?);

    stdout.print("Loading...\n", .{}) catch unreachable;

    const loading_start = std.time.milliTimestamp();

    var take = tk.load(alloc, &stream, &scene, &resources) catch |err| {
        std.debug.print("Loading take {} \n", .{err});
        return;
    };
    defer take.deinit(alloc);

    scene_loader.load(alloc, take.scene_filename, take, &scene) catch |err| {
        std.debug.print("Loading scene {} \n", .{err});
        return;
    };

    stdout.print("Loading time {d:.2} s\n", .{chrono.secondsSince(loading_start)}) catch unreachable;

    stdout.print("Rendering...\n", .{}) catch unreachable;

    const rendering_start = std.time.milliTimestamp();

    var driver = try rendering.Driver.init(alloc, &threads);
    defer driver.deinit(alloc);

    try driver.configure(alloc, &take.view, &scene);

    try driver.render(alloc, 0);
    driver.exportFrame();

    stdout.print("Total render time {d:.2} s\n", .{chrono.secondsSince(rendering_start)}) catch unreachable;
    const export_start = std.time.milliTimestamp();

    var png_writer = PngWriter.init(take.view.camera.sensor.alphaTransparency());
    defer png_writer.deinit(alloc);
    try png_writer.write(alloc, driver.target, &threads);

    stdout.print("Export time {d:.2} s\n", .{chrono.secondsSince(export_start)}) catch unreachable;
}
