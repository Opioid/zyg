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
const math = base.math;
const Pack4f = math.Pack4f;
const Threads = base.thread.Pool;

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

    for (options.inputs.items) |input| {
        log.info("Processing file {s}", .{input});

        const texture = core.tx.Provider.loadFile(alloc, input, .{}, .{ 1.0, 1.0 }, &resources) catch |e| {
            log.err("Could not load texture \"{s}\": {}", .{ input, e });
            continue;
        };

        try write(alloc, input, texture, options.exposure, options.format, scene, &threads);
    }

    log.info("Total render time {d:.2} s", .{chrono.secondsSince(loading_start)});
}

fn write(
    alloc: Allocator,
    name: []const u8,
    texture: core.tx.Texture,
    exposure: f32,
    format: Options.Format,
    scene: scn.Scene,
    threads: *Threads,
) !void {
    const desc = texture.description(scene);

    var context = Context{
        .texture = &texture,
        .target = try core.image.Float4.init(alloc, desc),
        .tonemapper = core.Tonemapper.init(.ACES, exposure),
        .scene = &scene,
    };
    defer context.target.deinit(alloc);

    _ = threads.runRange(&context, Context.run, 0, @intCast(u32, desc.dimensions.v[1]), 0);

    const alpha = texture.numChannels() > 3;

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
    try writer.write(alloc, buffered.writer(), context.target, threads);
    try buffered.flush();
}

const Context = struct {
    texture: *const core.tx.Texture,
    target: core.image.Float4,
    tonemapper: core.Tonemapper,
    scene: *const scn.Scene,

    pub fn run(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;

        var self = @intToPtr(*Context, context);

        const dim = self.texture.description(self.scene.*).dimensions;
        const width = dim.v[0];

        var y = begin;
        while (y < end) : (y += 1) {
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const ux = @intCast(i32, x);
                const uy = @intCast(i32, y);
                const color = self.texture.get2D_3(ux, uy, self.scene.*);
                const tm = self.tonemapper.tonemap(color);
                self.target.set2D(ux, uy, Pack4f.init4(tm[0], tm[1], tm[2], color[3]));
            }
        }
    }
};
