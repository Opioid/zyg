const Options = @import("options.zig").Options;
const exp = @import("exporter.zig");
const prj = @import("project.zig");
const Project = prj.Project;
const ProjectLoader = @import("project_loader.zig");

const util = @import("util");
const Graph = util.SceneGraph;
const SceneLoader = util.SceneLoader;

const core = @import("core");
const log = core.log;
const resource = core.resource;
const Sampler = core.sampler.Sampler;

const Camera = core.camera.Camera;
const Context = core.scn.Context;
const Vertex = core.scn.Vertex;
const Fragment = core.scn.shp.int.Fragment;
const Probe = core.scn.shp.Probe;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Transformation = math.Transformation;
const Ray = math.Ray;
const Vec2u = math.Vec2u;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;
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

    var stream = resources.fs.readStream(alloc, options.project) catch |err| {
        log.err("Open stream \"{s}\": {}", .{ options.project, err });
        return;
    };

    var project: Project = .{};
    defer project.deinit(alloc);

    try ProjectLoader.load(alloc, stream, &project);
    stream.deinit();

    graph.take.resolved_filename = try resources.fs.cloneLastResolvedName(alloc);
    graph.take.scene_filename = try alloc.dupe(u8, project.scene_filename);

    var scene_loader = SceneLoader.init(alloc, &resources, resource.MaterialProvider.createFallbackMaterial());
    defer scene_loader.deinit(alloc);

    scene_loader.load(alloc, &graph) catch |err| {
        log.err("Loading scene: {}", .{err});
    };

    var ortho = try createOrthoCamera(alloc, &graph);
    var camera = Camera{ .Orthographic = ortho };

    const context = Context{ .scene = &graph.scene, .camera = &camera, .layer = 0 };

    try graph.scene.compile(alloc, @splat(0.0), 0, &threads, fs);

    const region = graph.scene.aabb();
    const extent = region.extent();

    // Camera is only used in case material requests ray differentials
    const resolution = Vec2i{ @intFromFloat(@ceil(extent[0])), @intFromFloat(@ceil(extent[2])) };
    ortho.super.setResolution(resolution, .{ 0, 0, resolution[0], resolution[1] });
    ortho.update();

    const grid = project.grid;
    const fgrid: Vec2f = @floatFromInt(grid);

    var instances = List(prj.Instance){};
    defer instances.deinit(alloc);

    var rng: RNG = undefined;

    var sampler = Sampler{ .Sobol = undefined };

    var vertex = Vertex.init(undefined, 0);

    for (0..grid[1]) |y| {
        for (0..grid[0]) |x| {
            const id = y * grid[1] + x;
            rng.start(0, id);

            sampler.startPixel(0, rng.randomUint());

            const r = sampler.sample4D();
            const z_jitter = 2.0 * r[0] - 1.0;
            const x_jitter = 2.0 * r[1] - 1.0;
            const scale_jitter = 2.0 * r[2] - 1.0;
            const rotation_r = r[3];
            const mask_p = sampler.sample1D();

            const selected_prototype = project.prototype_distribution.sample(sampler.sample1D());

            const z_pos = region.bounds[0][2] + (@as(f32, @floatFromInt(y)) + 0.4 * z_jitter) * (extent[2] / fgrid[1]);
            const x_pos = region.bounds[0][0] + (@as(f32, @floatFromInt(x)) + 0.4 * x_jitter) * (extent[0] / fgrid[0]);

            vertex.probe = Probe.init(
                Ray.init(.{ x_pos, region.bounds[1][1] + 1.0, z_pos, 0.0 }, .{ 0.0, -1.0, 0.0, 0.0 }, 0.0, core.scn.ro.RayMaxT),
                0,
            );

            var frag: Fragment = undefined;

            if (!graph.scene.intersect(&vertex.probe, &frag)) {
                continue;
            }

            const mat_sample = vertex.sample(&frag, &sampler, .Off, context);

            const probability = mat_sample.aovAlbedo()[0];

            if (probability < 0.99999 and probability <= mask_p) {
                continue;
            }

            const trafo: Transformation = .{
                .position = frag.p,
                .scale = @splat(1.0 + 0.05 * scale_jitter),
                .rotation = math.quaternion.initRotationY(2.0 * std.math.pi * rotation_r),
            };

            try instances.append(alloc, .{ .prototype = selected_prototype, .transformation = trafo.toMat4x4() });
        }
    }

    try exp.Exporter.write(alloc, "test.json", project.prototypes, instances.items);
}

fn createOrthoCamera(alloc: Allocator, graph: *Graph) !core.camera.Orthographic {
    var ortho = core.camera.Orthographic{};

    const trafo = Transformation{
        .position = @splat(0.0),
        .scale = @splat(1.0),
        .rotation = math.quaternion.initRotationX(-math.degreesToRadians(90.0)),
    };

    graph.scene.calculateNumInterpolationFrames(ortho.super.frame_step, ortho.super.frame_duration);

    const entity_id = try graph.scene.createEntity(alloc);

    graph.scene.prop_space.setWorldTransformation(entity_id, trafo);

    ortho.super.entity = entity_id;

    return ortho;
}
