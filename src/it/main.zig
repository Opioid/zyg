const Options = @import("options.zig").Options;
const Operator = @import("operator.zig").Operator;

const core = @import("core");
const log = core.log;
const img = core.image;
const resource = core.resource;
const scn = core.scene;
const Tonemapper = core.rendering.Sensor.Tonemapper;

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

    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    var args = try std.process.argsWithAllocator(alloc);
    var options = try Options.parse(alloc, args);
    args.deinit();
    defer options.deinit(alloc);

    const num_workers = Threads.availableCores(options.threads);

    log.info("#Threads {}", .{num_workers});

    var threads: Threads = .{};
    try threads.configure(alloc, num_workers);
    defer threads.deinit(alloc);

    var resources = try resource.Manager.init(alloc, io, &threads);
    defer resources.deinit(alloc);

    var scene = try scn.Scene.init(alloc, &resources);
    defer scene.deinit(alloc);

    const loading_start = chrono.now(io);

    var image_options: Variants = .{};
    defer image_options.deinit(alloc);
    try image_options.set(alloc, "usage", core.tx.Usage.ColorAndOpacity);

    var operator = Operator{
        .class = options.operator,
        .tonemapper = Tonemapper.init(
            switch (options.operator) {
                .Tonemap => |tmc| tmc,
                else => .Linear,
            },
            options.exposure,
        ),
        .resources = &resources,
    };
    defer operator.deinit(alloc);

    try operator.guessMissingInputs(alloc, &options.inputs);

    var bytes_per_channel: u32 = 0;

    for (options.inputs.items) |input| {
        log.info("Loading file {s}", .{input});

        const texture = core.tx.Provider.loadFile(
            alloc,
            input,
            image_options,
            core.tx.Texture.DefaultMode,
            @splat(1.0),
            &resources,
        ) catch |e| {
            log.err("Could not load texture \"{s}\": {}", .{ input, e });
            continue;
        };

        try operator.textures.append(alloc, texture);

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

        const index = operator.baseItemOfIteration(i);

        const input_name = options.inputs.items[index];

        const num_outputs: u32 = @intCast(options.outputs.items.len);
        const output_name = if (num_outputs > 0) options.outputs.items[@min(num_outputs - 1, index)] else null;

        try write(alloc, input_name, output_name, operator.class, operator.target, &writer, encoding, format, &threads);
    }

    log.info("Total render time {d:.2} s", .{chrono.secondsSince(io, loading_start)});
}

fn write(
    alloc: Allocator,
    input_name: []const u8,
    output_name: ?[]const u8,
    operator: Operator.Class,
    target: core.image.Float4,
    image_writer: *core.ImageWriter,
    encoding: core.ImageWriter.Encoding,
    format: Options.Format,
    threads: *Threads,
) !void {
    if (.TXT == format) {
        const file_name = try buildName(alloc, input_name, output_name, "txt");
        defer alloc.free(file_name);

        var file = try std.fs.cwd().createFile(file_name, .{});
        defer file.close();

        var file_buffer: [4096]u8 = undefined;
        var txt_writer = file.writer(&file_buffer);

        var buffer: [256]u8 = undefined;

        const dim = target.dimensions;
        const num_pixels = img.Description.numPixels(dim);

        var line = try std.fmt.bufPrint(&buffer, "[{} * {}] = {{\n    ", .{ dim[0], dim[1] });
        _ = try txt_writer.interface.writeAll(line);

        for (target.pixels, 0..) |p, i| {
            line = try std.fmt.bufPrint(&buffer, "{d:.8},", .{p.v[0]});
            _ = try txt_writer.interface.writeAll(line);

            if (i < num_pixels - 1) {
                if (0 == ((i + 1) % 8)) {
                    _ = try txt_writer.interface.writeAll("\n    ");
                } else {
                    _ = try txt_writer.interface.writeAll(" ");
                }
            } else {
                _ = try txt_writer.interface.writeAll("\n");
            }
        }

        _ = try txt_writer.interface.writeAll("};\n");

        try txt_writer.end();

        log.info("Wrote file {s}", .{file_name});
    } else {
        const file_name = try buildName(alloc, input_name, output_name, image_writer.fileExtension());
        defer alloc.free(file_name);

        if (.Diff == operator) {
            var min: f32 = std.math.floatMax(f32);
            var max: f32 = 0.0;

            const dim = target.dimensions;

            const buffer = try alloc.alloc(f32, img.Description.numPixels(dim));
            defer alloc.free(buffer);

            for (target.pixels, 0..) |p, i| {
                const v = math.hmax3(.{ p.v[0], p.v[1], p.v[2], p.v[3] });

                buffer[i] = v;

                min = math.min(v, min);
                max = math.max(v, max);
            }

            try core.ImageWriter.PngWriter.writeHeatmap(
                alloc,
                dim[0],
                dim[1],
                buffer,
                min,
                max,
                file_name,
            );

            log.info("Wrote file {s}", .{file_name});
        } else {
            var file = try std.fs.cwd().createFile(file_name, .{});
            defer file.close();

            const d = target.dimensions;

            var file_buffer: [4096]u8 = undefined;
            var writer = file.writer(&file_buffer);
            try image_writer.write(alloc, &writer.interface, target, .{ 0, 0, d[0], d[1] }, encoding, threads);
            try writer.end();

            log.info("Wrote file {s}", .{file_name});
        }
    }
}

fn buildName(alloc: Allocator, input_name: []const u8, output_name: ?[]const u8, extension: []const u8) ![]const u8 {
    if (output_name) |name| {
        const ext_index = std.mem.lastIndexOf(u8, name, ".") orelse name.len;

        return std.fmt.allocPrint(alloc, "{s}.{s}", .{ name[0..ext_index], extension });
    } else {
        return std.fmt.allocPrint(alloc, "{s}.it.{s}", .{ input_name, extension });
    }
}
