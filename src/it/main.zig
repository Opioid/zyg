const Options = @import("options.zig").Options;
const Operator = @import("operator.zig").Operator;

const core = @import("core");
const log = core.log;
const resource = core.resource;
const scn = core.scn;
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

    // var da: std.heap.DebugAllocator(.{}) = .init;
    // defer _ = da.deinit();

    // const alloc = da.allocator();
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
        .tonemapper = core.Tonemapper.init(
            switch (options.operator) {
                .Tonemap => |tmc| tmc,
                else => .Linear,
            },
            options.exposure,
        ),
        .scene = &scene,
    };
    defer operator.deinit(alloc);

    var bytes_per_channel: u32 = 0;

    for (options.inputs.items, 0..) |input, i| {
        log.info("Loading file {s}", .{input});

        const texture = core.tx.Provider.loadFile(alloc, input, image_options, core.tx.Texture.DefaultMode, @splat(1.0), &resources) catch |e| {
            log.err("Could not load texture \"{s}\": {}", .{ input, e });
            continue;
        };

        try operator.textures.append(alloc, texture);
        try operator.input_ids.append(alloc, @intCast(i));

        bytes_per_channel = @max(bytes_per_channel, texture.bytesPerChannel());
    }

    resources.commitAsync();

    if (0 == operator.textures.items.len) {
        log.err("No items to operate on", .{});
        return;
    }

    try operator.configure(alloc);

    const encoding: core.ImageWriter.Encoding = switch (operator.textures.items[0].numChannels()) {
        0, 1 => .Float,
        2, 3 => .Color,
        else => .ColorAlpha,
    };

    const format = options.format orelse (if (bytes_per_channel > 1) Options.Format.EXR else Options.Format.PNG);

    var writer = switch (format) {
        .EXR => core.ImageWriter{ .EXR = .{ .half = true } },
        .PNG, .TXT => core.ImageWriter{ .PNG = core.ImageWriter.PngWriter.init(false) },
        .RGBE => core.ImageWriter{ .RGBE = .{} },
    };
    defer writer.deinit(alloc);

    var i: u32 = 0;
    const len = operator.iterations();
    while (i < len) : (i += 1) {
        operator.current = i;
        operator.run(&threads);

        const name = options.inputs.items[operator.baseItemOfIteration(i)];
        try write(alloc, name, operator.class, operator.target, &writer, encoding, format, &threads);
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
    format: Options.Format,
    threads: *Threads,
) !void {
    if (.TXT == format) {
        const output_name = try std.fmt.allocPrint(alloc, "{s}.it.{s}", .{ name, "txt" });
        defer alloc.free(output_name);

        var file = try std.fs.cwd().createFile(output_name, .{});
        defer file.close();

        const desc = target.description;
        const dim = desc.dimensions;

        const num_pixels = desc.numPixels();

        var buffered = std.io.bufferedWriter(file.writer());
        var txt_writer = buffered.writer();

        var buffer: [256]u8 = undefined;

        var line = try std.fmt.bufPrint(&buffer, "[{} * {}] = {{\n    ", .{ dim[0], dim[1] });
        _ = try txt_writer.write(line);

        for (target.pixels, 0..) |p, i| {
            line = try std.fmt.bufPrint(&buffer, "{d:.8},", .{p.v[0]});
            _ = try txt_writer.write(line);

            if (i < num_pixels - 1) {
                if (0 == ((i + 1) % 8)) {
                    _ = try txt_writer.write("\n    ");
                } else {
                    _ = try txt_writer.write(" ");
                }
            } else {
                _ = try txt_writer.write("\n");
            }
        }

        //   line = try std.fmt.bufPrint(&buffer, "};\n", .{});
        //    _ = try txt_writer.write(line);
        _ = try txt_writer.write("};\n");

        try buffered.flush();
    } else {
        const output_name = try std.fmt.allocPrint(alloc, "{s}.it.{s}", .{ name, writer.fileExtension() });
        defer alloc.free(output_name);

        if (.Diff == operator) {
            var min: f32 = std.math.floatMax(f32);
            var max: f32 = 0.0;

            const desc = target.description;

            const buffer = try alloc.alloc(f32, desc.numPixels());
            defer alloc.free(buffer);

            for (target.pixels, 0..) |p, i| {
                const v = math.hmax3(.{ p.v[0], p.v[1], p.v[2], p.v[3] });

                buffer[i] = v;

                min = math.min(v, min);
                max = math.max(v, max);
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
}
