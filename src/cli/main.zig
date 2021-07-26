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

    var rng = rnd.Generator.init(0, 0);

    var cam = &take.view.cam;

    const dim = cam.resolution;

    scene_loader.load(alloc, &scene) catch |err| {
        std.debug.print("error {} \n", .{err});
        return;
    };

    const camera_pos = scene.propWorldPosition(cam.entity);

    scene.compile(camera_pos);

    cam.update();

    cam.sensor.clear(0.0);

    const rendering_start = std.time.milliTimestamp();

    var isec = scn.prp.Intersection{};

    var y: i32 = 0;
    while (y < dim.v[1]) : (y += 1) {
        var x: i32 = 0;
        while (x < dim.v[0]) : (x += 1) {
            var hits: u32 = 0;

            var ns = Vec4f.init1(0.0);

            const num_samples = 16;

            const weight = 1.0 / @intToFloat(f32, num_samples);

            var s: u32 = 0;
            while (s < num_samples) : (s += 1) {
                const sample = sampler.Camera_sample{
                    .pixel = Vec2i.init2(x, y),
                    .pixel_uv = Vec2f.init2(rng.randomFloat(), rng.randomFloat()),
                };

                if (cam.generateRay(sample, scene)) |*ray| {
                    if (scene.intersect(ray, &isec)) {
                        hits += 1;
                        ns = ns.add3(isec.geo.n.addScalar3(1.0).mulScalar3(0.5).mulScalar3(weight));
                        // ns = isec.geo.n;

                        cam.sensor.addSample(sample, isec.geo.n.addScalar3(1.0).mulScalar3(0.5), Vec2i.init1(0));
                    } else {
                        cam.sensor.addSample(sample, Vec4f.init1(0.0), Vec2i.init1(0));
                    }
                }
            }
        }
    }

    var target = try image.Float4.init(alloc, image.Description{ .dimensions = Vec3i.init3(dim.v[0], dim.v[1], 1) });
    defer target.deinit(alloc);
    cam.sensor.resolve(&target);

    std.debug.print("Rendering time {} s\n", .{chrono.secondsSince(rendering_start)});
    const export_start = std.time.milliTimestamp();

    var png_writer = Png_writer{};
    defer png_writer.deinit(alloc);
    try png_writer.write(alloc, target);

    std.debug.print("Export time {} s\n", .{chrono.secondsSince(export_start)});
}
