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

    var args = try std.process.argsWithAllocator(alloc);
    var options = try Options.parse(alloc, args);
    args.deinit();
    defer options.deinit(alloc);

    const num_workers = Threads.availableCores(options.threads);

    log.info("#Threads {}", .{num_workers});

    var threads: Threads = .{};
    try threads.configure(alloc, num_workers);
    defer threads.deinit(alloc);

    var scene = try scn.Scene.init(alloc);
    defer scene.deinit(alloc);

    var resources = try resource.Manager.init(alloc, &scene, &threads);
    defer resources.deinit(alloc);

    const loading_start = std.time.milliTimestamp();

    var image_options: Variants = .{};
    defer image_options.deinit(alloc);
    try image_options.set(alloc, "usage", core.tx.Usage.ColorAndOpacity);

    var operator = Operator{
        .class = options.operator,
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

    if (0 == operator.textures.items.len) {
        log.err("No items to operate on", .{});
        return;
    }

    try operator.configure(alloc);

    const encoding: core.ImageWriter.Encoding = switch (operator.textures.items[0].numChannels()) {
        0, 1 => .Float,
        2, 3 => .Color,
        else => .Color_alpha,
    };

    var writer = switch (options.format) {
        .EXR => core.ImageWriter{ .EXR = .{ .half = true } },
        .PNG => core.ImageWriter{ .PNG = core.ImageWriter.PngWriter.init(false) },
        .RGBE => core.ImageWriter{ .RGBE = .{} },
    };
    defer writer.deinit(alloc);

    var i: u32 = 0;
    const len = operator.iterations();
    while (i < len) : (i += 1) {
        operator.current = i;
        operator.run(&threads);

        const name = options.inputs.items[operator.input_ids.items[i]];
        try write(alloc, name, operator.class, operator.target, &writer, encoding, &threads);
    }

    log.info("Total render time {d:.2} s", .{chrono.secondsSince(loading_start)});
}

fn write(
    alloc: Allocator,
    name: []const u8,
    operator: Operator.Class,
    target: core.image.Float4,
    writer: *core.ImageWriter,
    encoding: core.ImageWriter.Encoding,
    threads: *Threads,
) !void {
    var output_name = try std.fmt.allocPrint(alloc, "{s}.it.{s}", .{ name, writer.fileExtension() });
    defer alloc.free(output_name);

    if (.Diff == operator) {
        var min: f32 = std.math.f32_max;
        var max: f32 = 0.0;

        const desc = target.description;

        const buffer = try alloc.alloc(f32, desc.numPixels());
        defer alloc.free(buffer);

        for (target.pixels) |p, i| {
            const v = math.maxComponent3(.{ p.v[0], p.v[1], p.v[2], p.v[3] });

            buffer[i] = v;

            min = std.math.min(v, min);
            max = std.math.max(v, max);
        }

        try core.ImageWriter.PngWriter.writeHeatmap(
            alloc,
            desc.dimensions[0],
            desc.dimensions[1],
            buffer,
            min,
            max,
            output_name,
        );
    } else {
        var file = try std.fs.cwd().createFile(output_name, .{});
        defer file.close();

        const d = target.description.dimensions;

        var buffered = std.io.bufferedWriter(file.writer());
        try writer.write(alloc, buffered.writer(), target, .{ 0, 0, d[0], d[1] }, encoding, threads);
        try buffered.flush();
    }
}
