const Options = @import("options.zig").Options;
const Operator = @import("operator.zig").Operator;

const core = @import("core");
const log = core.log;
const rendering = core.rendering;
const resource = core.resource;
const scn = core.scn;
const thread = base.thread;
const tk = core.tk;

const base = @import("base");
const chrono = base.chrono;
const math = base.math;
const Pack4f = math.Pack4f;
const Threads = base.thread.Pool;
const Variants = base.memory.VariantMap;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    log.info("Welcome to it!", .{});

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

    const num_workers = Threads.availableCores(options.threads);

    log.info("#Threads {}", .{num_workers});

    var threads: Threads = .{};
    try threads.configure(alloc, num_workers);
    defer threads.deinit(alloc);

    var resources = try resource.Manager.init(alloc, &threads);
    defer resources.deinit(alloc);

    var scene = try scn.Scene.init(
        alloc,
        &resources.images.resources,
        &resources.materials.resources,
        &resources.shapes.resources,
        0,
    );
    defer scene.deinit(alloc);

    const loading_start = std.time.milliTimestamp();

    var image_options: Variants = .{};
    defer image_options.deinit(alloc);
    try image_options.set(alloc, "usage", core.tx.Usage.ColorAndOpacity);

    var operator = Operator{
        .typef = options.operator,
        .tonemapper = core.Tonemapper.init(if (.Tonemap == options.operator) .ACES else .Linear, options.exposure),
        .scene = &scene,
    };
    defer operator.deinit(alloc);

    for (options.inputs.items) |input, i| {
        log.info("Loading file {s}", .{input});

        const texture = core.tx.Provider.loadFile(alloc, input, image_options, .{ 1.0, 1.0 }, &resources) catch |e| {
            log.err("Could not load texture \"{s}\": {}", .{ input, e });
            continue;
        };

        try operator.textures.append(alloc, texture);
        try operator.input_ids.append(alloc, @intCast(u32, i));
    }

    try operator.configure(alloc);

    const alpha = operator.textures.items[0].numChannels() > 3;

    if (operator.typef.cummulative()) {
        operator.run(&threads);

        try write(
            alloc,
            options.inputs.items[operator.input_ids.items[0]],
            operator.target,
            alpha,
            options.format,
            &threads,
        );
    } else {
        for (operator.textures.items) |_, i| {
            operator.current = @intCast(u32, i);
            operator.run(&threads);

            try write(
                alloc,
                options.inputs.items[operator.input_ids.items[i]],
                operator.target,
                alpha,
                options.format,
                &threads,
            );
        }
    }

    // for (options.inputs.items) |input| {
    //     log.info("Processing file {s}", .{input});

    //     const texture = core.tx.Provider.loadFile(alloc, input, image_options, .{ 1.0, 1.0 }, &resources) catch |e| {
    //         log.err("Could not load texture \"{s}\": {}", .{ input, e });
    //         continue;
    //     };

    //     try write(alloc, input, texture, options.exposure, options.format, scene, &threads);
    // }

    log.info("Total render time {d:.2} s", .{chrono.secondsSince(loading_start)});
}

fn write(
    alloc: Allocator,
    name: []const u8,
    target: core.image.Float4,
    alpha: bool,
    format: Options.Format,
    threads: *Threads,
) !void {
    var writer = switch (format) {
        .EXR => core.ImageWriter{ .EXR = .{ .half = true, .alpha = alpha } },
        .PNG => core.ImageWriter{ .PNG = core.ImageWriter.PngWriter.init(false, alpha) },
        .RGBE => core.ImageWriter{ .RGBE = .{} },
    };
    defer writer.deinit(alloc);

    var output_name = try std.fmt.allocPrint(alloc, "{s}.it.{s}", .{ name, writer.fileExtension() });
    defer alloc.free(output_name);
    var file = try std.fs.cwd().createFile(output_name, .{});
    defer file.close();

    var buffered = std.io.bufferedWriter(file.writer());
    try writer.write(alloc, buffered.writer(), target, threads);
    try buffered.flush();
}
