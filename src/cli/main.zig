const base = @import("base");
usingnamespace base;
usingnamespace base.math;

usingnamespace @import("core");

const Png_writer = image.encoding.png.Writer;

const Options = @import("options/options.zig").Options;

const std = @import("std");

pub fn main() !void {
    std.debug.print("Welcome to zyg!\n", .{});

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

    std.debug.print("scene {s} \n", .{take.scene_filename});

    scene_loader.load(alloc, &scene) catch |err| {
        std.debug.print("error {} \n", .{err});
        return;
    };

    const rendering_start = std.time.milliTimestamp();

    var driver = try rendering.Driver.init(alloc);
    defer driver.deinit(alloc);

    try driver.configure(alloc, &take.view, &scene);

    driver.render();
    driver.exportFrame();

    std.debug.print("Rendering time {} s\n", .{chrono.secondsSince(rendering_start)});
    const export_start = std.time.milliTimestamp();

    var png_writer = Png_writer{};
    defer png_writer.deinit(alloc);
    try png_writer.write(alloc, driver.target);

    std.debug.print("Export time {} s\n", .{chrono.secondsSince(export_start)});
}
