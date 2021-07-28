const base = @import("base");
usingnamespace base;
usingnamespace base.math;

usingnamespace @import("core");

const Png_writer = image.encoding.png.Writer;

const Options = @import("options/options.zig").Options;

const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    stdout.print("Welcome to zyg!\n", .{}) catch unreachable;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked) {
            std.debug.print("Memory leak {} \n", .{leaked});
        }
    }

    const alloc = &gpa.allocator;
    //   const alloc = std.heap.page_allocator;

    var options = try Options.parse(alloc, std.process.args());
    defer options.deinit(alloc);

    const num_workers = thread.Pool.availableCores(options.threads);

    stdout.print("#Threads {}\n", .{num_workers}) catch unreachable;

    var threads: thread.Pool = undefined;
    try threads.configure(alloc, num_workers);
    defer threads.deinit(alloc);

    var resources = resource.Manager.init(alloc);
    defer resources.deinit(alloc);

    var scene_loader = try scn.Loader.init(alloc, &resources);

    var scene = try scn.Scene.init(alloc, &resources.shapes.resources, scene_loader.null_shape);
    defer scene.deinit(alloc);

    var take = tk.load(alloc, &scene) catch |err| {
        std.debug.print("error {} \n", .{err});
        return;
    };
    defer take.deinit(alloc);

    scene_loader.load(alloc, &scene) catch |err| {
        std.debug.print("error {} \n", .{err});
        return;
    };

    stdout.print("Rendering...\n", .{}) catch unreachable;

    const rendering_start = std.time.milliTimestamp();

    var driver = try rendering.Driver.init(alloc);
    defer driver.deinit(alloc);

    try driver.configure(alloc, &take.view, &scene);

    driver.render();
    driver.exportFrame();

    stdout.print("Rendering time {d} s\n", .{chrono.secondsSince(rendering_start)}) catch unreachable;
    const export_start = std.time.milliTimestamp();

    var png_writer = Png_writer{};
    defer png_writer.deinit(alloc);
    try png_writer.write(alloc, driver.target);

    stdout.print("Export time {d} s\n", .{chrono.secondsSince(export_start)}) catch unreachable;
}
