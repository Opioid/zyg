const Options = @import("options.zig").Options;
const exp = @import("exporter.zig");

const util = @import("util");
const Graph = util.SceneGraph;
const SceneLoader = util.SceneLoader;

const core = @import("core");
const log = core.log;
const resource = core.resource;

const Fragment = core.scn.shp.int.Fragment;
const Probe = core.scn.shp.Probe;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Trafo = math.Transformation;
const Ray = math.Ray;
const Vec2u = math.Vec2u;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;
const Threads = base.thread.Pool;

const std = @import("std");
const List = std.ArrayListUnmanaged;

pub fn main() !void {
    log.info("Welcome to sow!", .{});

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

    // try core.ggx_integrate.integrate(alloc, &threads);
    // try core.rainbow_integrate.integrate(alloc);
    // try core.image.testing.write_reference_normal_map(alloc, "reference_normal.png");

    var graph = try Graph.init(alloc);
    defer graph.deinit(alloc);

    var resources = try resource.Manager.init(alloc, &graph.scene, &threads);
    defer resources.deinit(alloc);

    resources.materials.provider.setSettings(false, false, false);

    var fs = &resources.fs;

    if (0 == options.mounts.items.len) {
        try fs.pushMount(alloc, "../data");
    } else {
        for (options.mounts.items) |i| {
            try fs.pushMount(alloc, i);
        }
    }

    var scene_loader = SceneLoader.init(alloc, &resources, resource.MaterialProvider.createFallbackMaterial());
    defer scene_loader.deinit(alloc);

    graph.take.scene_filename = try alloc.dupe(u8, "sow/buried_sphere.scene");

    scene_loader.load(alloc, &graph) catch |err| {
        log.err("Loading scene: {}", .{err});
    };

    try graph.scene.compile(alloc, @splat(0.0), 0, &threads, fs);

    var prototypes = List(exp.Prototype){};
    defer prototypes.deinit(alloc);

    var prototype: exp.Prototype = undefined;
    prototype.shape_file = try alloc.dupe(u8, "senecio_3.sub.gz");
    prototype.materials = try alloc.alloc([]u8, 2);
    prototype.materials[0] = try alloc.dupe(u8, "senecio_branch_1.material");
    prototype.materials[1] = try alloc.dupe(u8, "senecio_leaf_1.material");

    try prototypes.append(alloc, prototype);

    defer {
        for (prototypes.items) |*p| {
            p.deinit(alloc);
        }
    }

    var instances = List(exp.Instance){};
    defer instances.deinit(alloc);

    const region = graph.scene.aabb();
    const extent = region.extent();

    const dimensions = Vec2u{ 40, 40 };
    const fdim: Vec2f = @floatFromInt(dimensions);

    var rng = RNG.init(0, 0);

    for (0..dimensions[1]) |y| {
        for (0..dimensions[0]) |x| {
            const z_jitter = 2.0 * rng.randomFloat() - 1.0;
            const x_jitter = 2.0 * rng.randomFloat() - 1.0;
            const scale_jitter = 2.0 * rng.randomFloat() - 1.0;

            const z_pos = region.bounds[0][2] + (@as(f32, @floatFromInt(y)) + 0.4 * z_jitter) * (extent[2] / fdim[1]);
            const x_pos = region.bounds[0][0] + (@as(f32, @floatFromInt(x)) + 0.4 * x_jitter) * (extent[0] / fdim[0]);

            var probe = Probe.init(
                Ray.init(.{ x_pos, region.bounds[1][1] + 1.0, z_pos, 0.0 }, .{ 0.0, -1.0, 0.0, 0.0 }, 0.0, core.scn.ro.RayMaxT),
                0,
            );

            var frag: Fragment = undefined;

            if (!graph.scene.intersect(&probe, &frag)) {
                continue;
            }

            const trafo: Trafo = .{
                .position = frag.p,
                .scale = @splat(1.0 + 0.05 * scale_jitter),
                .rotation = math.quaternion.initRotationY(2.0 * std.math.pi * rng.randomFloat()),
            };

            try instances.append(alloc, .{ .prototype = 0, .transformation = trafo.toMat4x4() });
        }
    }

    try exp.Exporter.write(alloc, "test.json", prototypes.items, instances.items);
}
