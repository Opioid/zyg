const base = @import("base");
usingnamespace base;
usingnamespace base.math;

usingnamespace @import("core");

const Png_writer = image.encoding.png.Writer;

const Options = @import("options/options.zig").Options;

const std = @import("std");

pub fn main() !void {
    // const f = try std.fs.cwd().openFile("text.txt", .{});
    // //    var reader = std.io.bufferedReader(f.reader());

    // var read_stream = file.ReadStream.init(f);
    // defer read_stream.deinit();

    // var buf: [4]u8 = undefined;

    // //_ = try reader.read(buf[0..]);
    // _ = try read_stream.read(buf[0..]);
    // std.debug.print("{s}", .{buf});

    // try read_stream.seekTo(0);

    // _ = try read_stream.read(buf[0..]);
    // std.debug.print("{s}", .{buf});

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

    var threads: thread.Pool = .{};
    try threads.configure(alloc, num_workers);
    defer threads.deinit(alloc);

    var resources = resource.Manager{};

    resources.shapes = resource.Shapes.init(alloc, resource.Triangle_mesh_provider{});

    defer resources.deinit(alloc);

    var fs = &resources.fs;

    if (0 == options.mounts.items.len) {
        try fs.pushMount(alloc, "../data");
    } else {
        for (options.mounts.items) |i| {
            try fs.pushMount(alloc, i);
        }
    }

    var scene_loader = scn.Loader.init(alloc, &resources);

    var scene = try scn.Scene.init(alloc, &resources.shapes.resources, scene_loader.null_shape);
    defer scene.deinit(alloc);

    var take = tk.load(alloc, &scene, &resources) catch |err| {
        std.debug.print("Loading take {} \n", .{err});
        return;
    };
    defer take.deinit(alloc);

    scene_loader.load(alloc, take.scene_filename, &scene) catch |err| {
        std.debug.print("Loading scene {} \n", .{err});
        return;
    };

    var driver = try rendering.Driver.init(alloc, &threads);
    defer driver.deinit(alloc);

    stdout.print("Rendering...\n", .{}) catch unreachable;

    const rendering_start = std.time.milliTimestamp();

    try driver.configure(alloc, &take.view, &scene);

    driver.render();
    driver.exportFrame();

    stdout.print("Rendering time {d:.2} s\n", .{chrono.secondsSince(rendering_start)}) catch unreachable;
    const export_start = std.time.milliTimestamp();

    var png_writer = Png_writer.init(take.view.camera.sensor.alphaTransparency());
    defer png_writer.deinit(alloc);
    try png_writer.write(alloc, driver.target);

    stdout.print("Export time {d:.2} s\n", .{chrono.secondsSince(export_start)}) catch unreachable;
}
