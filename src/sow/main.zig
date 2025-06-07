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
const Shape = core.scn.Shape;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Transformation = math.Transformation;
const Ray = math.Ray;
const Mat3x3 = math.Mat3x3;
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

    var threads: Threads = .{};
    try threads.configure(alloc, num_workers);
    defer threads.deinit(alloc);

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

    ProjectLoader.load(alloc, stream, &project) catch |err| {
        log.err("Loading project: {}", .{err});
        return;
    };

    stream.deinit();

    if (0 == project.prototypes.len) {
        log.err("No prototypes specified.", .{});
        return;
    }

    graph.take.resolved_filename = try resources.fs.cloneLastResolvedName(alloc);
    graph.take.scene_filename = try alloc.dupe(u8, project.scene_filename);

    var scene_loader = SceneLoader.init(alloc, &resources, resource.MaterialProvider.createFallbackMaterial());
    defer scene_loader.deinit(alloc);

    scene_loader.load(alloc, &graph) catch |err| {
        log.err("Loading scene: {}", .{err});
        return;
    };

    var ortho = try createOrthoCamera(alloc, &graph);
    var camera = Camera{ .Orthographic = ortho };

    const context = Context{ .scene = &graph.scene, .camera = &camera, .layer = 0 };

    try graph.scene.compile(alloc, @splat(0.0), 0, &threads, fs);

    const region = graph.scene.aabb();
    const extent = region.extent();

    var max_prototype_extent: Vec4f = @splat(0.0);

    {
        if (project.mount_folder.len > 0) {
            try resources.fs.pushMount(alloc, project.mount_folder);
        }

        var proto_ids = try alloc.alloc(u32, project.prototypes.len);
        defer alloc.free(proto_ids);

        for (project.prototypes, 0..) |p, i| {
            const proto_shape = try (if (p.shape_file.len > 0) resources.loadFile(Shape, alloc, p.shape_file, .{}) else SceneLoader.getShape(p.shape_type));
            const proto_id = try graph.scene.createPropShape(alloc, proto_shape, &.{}, false, true);
            proto_ids[i] = proto_id;
        }

        resources.commitAsync();

        for (project.prototypes, proto_ids) |p, proto_id| {
            const proto_inst = graph.scene.prop(proto_id);

            const aabb = proto_inst.localAabb(&graph.scene).transform(p.trafo.toMat4x4());

            max_prototype_extent = math.max4(max_prototype_extent, aabb.extent());
        }

        if (project.mount_folder.len > 0) {
            resources.fs.popMount(alloc);
        }
    }

    // Camera is only used in case material requests ray differentials
    const resolution = Vec2i{ @intFromFloat(@ceil(extent[0])), @intFromFloat(@ceil(extent[2])) };
    ortho.super.setResolution(resolution, .{ 0, 0, resolution[0], resolution[1] });
    ortho.update();

    const cell_extent = math.max(max_prototype_extent[0], max_prototype_extent[2]) / project.density;

    const grid = Vec2u{
        @intFromFloat(@ceil(extent[0] / cell_extent)),
        @intFromFloat(@ceil(extent[2] / cell_extent)),
    };

    log.info("Grid: {}", .{grid});

    const fgrid: Vec2f = @floatFromInt(grid);

    var instances = List(prj.Instance){};
    defer instances.deinit(alloc);

    var rng: RNG = undefined;

    const y_order = try alloc.alloc(f32, grid[0] * grid[1]);
    defer alloc.free(y_order);

    // if (project.ortho_mode) {
    //     var offset: f32 = 0.0;
    //     for (y_order) |*o| {
    //         o.* = offset;
    //         offset -= 0.01;
    //     }

    //     rng.start(0, 0);
    //     base.rnd.biasedShuffle(f32, y_order, &rng);
    // } else {
    for (y_order) |*o| {
        o.* = 0.0;
    }
    // }

    var sampler = Sampler{ .Sobol = undefined };

    var vertex = Vertex.init(undefined, 0);

    for (0..grid[1]) |y| {
        for (0..grid[0]) |x| {
            const id = y * grid[1] + x;
            rng.start(0, id);

            sampler.startPixel(0, rng.randomUint());

            const r0 = sampler.sample4D();

            const depth_r = r0[0];
            const x_r = 2.0 * r0[1] - 1.0;
            const z_r = 2.0 * r0[2] - 1.0;
            const scale_r = r0[3];

            const mask_p = sampler.sample1D();

            const r1 = sampler.sample4D();
            const rotation_r = r1[0];
            const incline_x_r = 2.0 * r1[1] - 1.0;
            const incline_z_r = 2.0 * r1[2] - 1.0;

            const selected_prototype_id = project.prototype_distribution.sample(r1[3]);
            const prototype = project.prototypes[selected_prototype_id];

            const pos_jitter = @as(Vec2f, @splat(0.5)) * prototype.position_jitter;

            const x_pos = region.bounds[0][0] + (@as(f32, @floatFromInt(x)) + 0.5 + pos_jitter[0] * x_r) * (extent[0] / fgrid[0]);
            const z_pos = region.bounds[0][2] + (@as(f32, @floatFromInt(y)) + 0.5 + pos_jitter[1] * z_r) * (extent[2] / fgrid[1]);

            vertex.probe = Probe.init(
                Ray.init(.{ x_pos, region.bounds[1][1] + 1.0, z_pos, 0.0 }, .{ 0.0, -1.0, 0.0, 0.0 }, 0.0, core.scn.ro.RayMaxT),
                0,
            );

            var frag: Fragment = undefined;
            if (!graph.scene.intersect(&vertex.probe, &sampler, &frag)) {
                continue;
            }

            const mat_sample = vertex.sample(&frag, &sampler, .Off, context);

            const probability = mat_sample.aovAlbedo()[0];

            if (probability < 0.99999 and probability <= mask_p) {
                continue;
            }

            const Y = Vec4f{ 0.0, 1.0, 0.0, 0.0 };
            const up = if (project.align_to_normal) mat_sample.super().shadingNormal() else Y;
            const basis = math.quaternion.initFromMat3x3(Mat3x3.initRotationAlign(Y, up));

            const rotation = math.quaternion.initRotationY((2.0 * std.math.pi) * rotation_r);

            const incline_x = math.quaternion.initRotationX(std.math.pi * prototype.incline_jitter[0] * incline_x_r);
            const incline_z = math.quaternion.initRotationZ(std.math.pi * prototype.incline_jitter[1] * incline_z_r);

            const depth_offset = math.lerp(project.depth_offset_range[0], project.depth_offset_range[1], depth_r);

            const local_trafo: Transformation = .{
                .position = frag.p + Vec4f{ 0.0, y_order[id] + depth_offset, 0.0, 0.0 },
                .scale = @splat(math.lerp(prototype.scale_range[0], prototype.scale_range[1], scale_r)),
                .rotation = math.quaternion.mul(math.quaternion.mul(math.quaternion.mul(incline_x, incline_z), rotation), basis),
            };

            const trafo = local_trafo.transform(prototype.trafo);

            try instances.append(alloc, .{ .prototype = selected_prototype_id, .transformation = trafo.toMat4x4() });

            if (project.tileable) {
                if (0 == y) {
                    var tile_trafo = trafo;
                    tile_trafo.position[2] += extent[2];
                    try instances.append(alloc, .{ .prototype = selected_prototype_id, .transformation = tile_trafo.toMat4x4() });
                } else if (grid[1] - 1 == y) {
                    var tile_trafo = trafo;
                    tile_trafo.position[2] -= extent[2];
                    try instances.append(alloc, .{ .prototype = selected_prototype_id, .transformation = tile_trafo.toMat4x4() });
                }

                if (0 == x) {
                    var tile_trafo = trafo;
                    tile_trafo.position[0] += extent[0];
                    try instances.append(alloc, .{ .prototype = selected_prototype_id, .transformation = tile_trafo.toMat4x4() });
                } else if (grid[0] - 1 == x) {
                    var tile_trafo = trafo;
                    tile_trafo.position[0] -= extent[0];
                    try instances.append(alloc, .{ .prototype = selected_prototype_id, .transformation = tile_trafo.toMat4x4() });
                }
            }
        }
    }

    try exp.Exporter.write(alloc, options.output, project.materials.items, project.prototypes, instances.items);
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
