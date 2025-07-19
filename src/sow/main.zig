const Options = @import("options.zig").Options;
const InstancerExporter = @import("instancer_exporter.zig").Exporter;
const ParticleExporter = @import("particle/particle_exporter.zig").Exporter;
const prt = @import("particle/particle_generator.zig");
const ParticleGenerator = prt.Generator;
const prj = @import("project.zig");
const Project = prj.Project;
const ProjectLoader = @import("project_loader.zig");

const merger = @import("triangle_motion_merger.zig");

const util = @import("util");
const Graph = util.SceneGraph;
const SceneLoader = util.SceneLoader;

const core = @import("core");
const log = core.log;
const Resources = core.resource.Manager;
const Sampler = core.sampler.Sampler;

const Camera = core.camera.Camera;
const Context = core.scene.Context;
const Vertex = core.scene.Vertex;
const Fragment = core.scene.shp.int.Fragment;
const Probe = core.scene.shp.Probe;
const Shape = core.scene.Shape;

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

    var resources = try Resources.init(alloc, &graph.scene, &threads);
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

    if (try merger.merge(alloc, &resources)) {
        log.info("We end the merger", .{});
        return;
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

    if (project.particles.num_particles > 0) {
        var particles: prt.Particles = undefined;
        defer particles.deinit(alloc);

        try ParticleGenerator.generateSparks(alloc, project, &particles);

        try ParticleExporter.write(alloc, options.output, &particles);
    } else {
        if (0 == project.scene_filename.len) {
            log.err("No scene file specified.", .{});
            return;
        }

        if (0 == project.prototypes.len) {
            log.err("No prototypes specified.", .{});
            return;
        }

        graph.take.resolved_filename = try resources.fs.cloneLastResolvedName(alloc);
        graph.take.scene_filename = try alloc.dupe(u8, project.scene_filename);

        var scene_loader = SceneLoader.init(alloc, &resources, Resources.MaterialProvider.createFallbackMaterial());
        defer scene_loader.deinit(alloc);

        scene_loader.load(alloc, &graph) catch |err| {
            log.err("Loading scene: {}", .{err});
            return;
        };

        const ortho = try createOrthoCamera(alloc, &graph);
        var camera = Camera{ .Orthographic = ortho };

        const context = Context{ .scene = &graph.scene, .camera = &camera, .layer = 0 };

        try graph.scene.compile(alloc, @splat(0.0), 0, &threads, fs);

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

        var instances = List(prj.Instance){};
        defer instances.deinit(alloc);

        if (project.triplanar) {
            try scatter(alloc, &project, context, .XPos, max_prototype_extent, &instances);
            try scatter(alloc, &project, context, .XNeg, max_prototype_extent, &instances);
            try scatter(alloc, &project, context, .YPos, max_prototype_extent, &instances);
            try scatter(alloc, &project, context, .YNeg, max_prototype_extent, &instances);
            try scatter(alloc, &project, context, .ZPos, max_prototype_extent, &instances);
            try scatter(alloc, &project, context, .ZNeg, max_prototype_extent, &instances);
        } else {
            try scatter(alloc, &project, context, .YPos, max_prototype_extent, &instances);
        }

        try InstancerExporter.write(alloc, options.output, project.materials.items, project.prototypes, instances.items);
    }
}

fn createOrthoCamera(alloc: Allocator, graph: *Graph) !core.camera.Orthographic {
    var ortho = core.camera.Orthographic{};

    graph.scene.calculateNumInterpolationFrames(ortho.super.frame_step, ortho.super.frame_duration);

    ortho.super.entity = try graph.scene.createEntity(alloc);

    return ortho;
}

const Up = enum {
    XPos,
    XNeg,
    YPos,
    YNeg,
    ZPos,
    ZNeg,

    pub fn cameraRotation(self: Up) math.Quaternion {
        return switch (self) {
            .XPos => math.quaternion.initRotationY(-math.degreesToRadians(90.0)),
            .XNeg => math.quaternion.initRotationY(math.degreesToRadians(90.0)),
            .YPos => math.quaternion.initRotationX(-math.degreesToRadians(90.0)),
            .YNeg => math.quaternion.initRotationX(math.degreesToRadians(90.0)),
            .ZPos => math.quaternion.initRotationZ(-math.degreesToRadians(90.0)),
            .ZNeg => math.quaternion.initRotationZ(math.degreesToRadians(90.0)),
        };
    }

    pub fn worldAxis(self: Up) [3]u32 {
        return switch (self) {
            .XPos, .XNeg => .{ 2, 1, 0 },
            .YPos, .YNeg => .{ 0, 2, 1 },
            .ZPos, .ZNeg => .{ 0, 1, 2 },
        };
    }

    pub fn ray(self: Up, region: AABB, x: f32, y: f32) Ray {
        return switch (self) {
            .XPos => Ray.init(.{ region.bounds[1][0] + 1.0, x, y, 0.0 }, .{ -1.0, 0.0, 0.0, 0.0 }, 0.0, core.scene.ro.RayMaxT),
            .XNeg => Ray.init(.{ region.bounds[0][0] - 1.0, x, y, 0.0 }, .{ 1.0, 0.0, 0.0, 0.0 }, 0.0, core.scene.ro.RayMaxT),
            .YPos => Ray.init(.{ x, region.bounds[1][1] + 1.0, y, 0.0 }, .{ 0.0, -1.0, 0.0, 0.0 }, 0.0, core.scene.ro.RayMaxT),
            .YNeg => Ray.init(.{ x, region.bounds[0][1] - 1.0, y, 0.0 }, .{ 0.0, 1.0, 0.0, 0.0 }, 0.0, core.scene.ro.RayMaxT),
            .ZPos => Ray.init(.{ x, y, region.bounds[1][1] + 1.0, 0.0 }, .{ 0.0, 0.0, -1.0, 0.0 }, 0.0, core.scene.ro.RayMaxT),
            .ZNeg => Ray.init(.{ x, y, region.bounds[0][1] - 1.0, 0.0 }, .{ 0.0, 0.0, 1.0, 0.0 }, 0.0, core.scene.ro.RayMaxT),
        };
    }

    pub fn triplanarContribution(self: Up, n: Vec4f) bool {
        const an = @abs(n);
        return switch (self) {
            .XPos, .XNeg => an[0] > an[1] and an[0] > an[2],
            .YPos, .YNeg => an[1] > an[0] and an[1] > an[2],
            .ZPos, .ZNeg => an[2] > an[0] and an[2] > an[1],
        };
    }
};

fn scatter(
    alloc: Allocator,
    project: *const Project,
    context: Context,
    world_up: Up,
    max_prototype_extent: Vec4f,
    instances: *List(prj.Instance),
) !void {
    const camera_trafo = Transformation{
        .position = @splat(0.0),
        .scale = @splat(1.0),
        .rotation = world_up.cameraRotation(),
    };

    context.scene.prop_space.setWorldTransformation(context.camera.super().entity, camera_trafo);

    const region = context.scene.aabb();
    const extent = region.extent();

    const world_axis = world_up.worldAxis();
    const world_extent = Vec2f{ extent[world_axis[0]], extent[world_axis[1]] };

    const resolution = Vec2i{ @intFromFloat(@ceil(world_extent[0])), @intFromFloat(@ceil(world_extent[1])) };
    context.camera.super().setResolution(resolution, .{ 0, 0, resolution[0], resolution[1] });
    context.camera.update(0, context.scene);

    var cell_extent: f32 = undefined;

    if (project.triplanar) {
        cell_extent = math.max(max_prototype_extent[0], max_prototype_extent[2]) / project.density;
    } else {
        cell_extent = math.max(max_prototype_extent[world_axis[0]], max_prototype_extent[world_axis[1]]) / project.density;
    }

    const grid = Vec2u{
        @intFromFloat(@ceil(world_extent[0] / cell_extent)),
        @intFromFloat(@ceil(world_extent[1] / cell_extent)),
    };

    log.info("Grid: {}", .{grid});

    const fgrid: Vec2f = @floatFromInt(grid);

    var rng: RNG = undefined;

    const y_order = try alloc.alloc(f32, grid[0] * grid[1]);
    defer alloc.free(y_order);

    var sampler = Sampler{ .Sobol = undefined };

    var vertex = Vertex.init(undefined, 0);

    for (0..grid[1]) |y| {
        for (0..grid[0]) |x| {
            const id = y * grid[1] + x;

            if (project.triplanar) {
                rng.start(0, @as(u32, (0xFFFFFFFF / 6)) * @intFromEnum(world_up) + id);
            } else {
                rng.start(0, id);
            }

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

            const x_pos = region.bounds[0][world_axis[0]] + (@as(f32, @floatFromInt(x)) + 0.5 + pos_jitter[0] * x_r) * (world_extent[0] / fgrid[0]);
            const y_pos = region.bounds[0][world_axis[1]] + (@as(f32, @floatFromInt(y)) + 0.5 + pos_jitter[1] * z_r) * (world_extent[1] / fgrid[1]);

            vertex.probe = Probe.init(world_up.ray(region, x_pos, y_pos), 0);

            var frag: Fragment = undefined;
            if (!context.scene.intersect(&vertex.probe, &sampler, &frag)) {
                continue;
            }

            const mat_sample = vertex.sample(&frag, &sampler, .Off, context);

            const probability = mat_sample.aovAlbedo()[0];

            if (probability < 0.99999 and probability <= mask_p) {
                continue;
            }

            const n = mat_sample.super().shadingNormal();

            if (project.triplanar and !world_up.triplanarContribution(n)) {
                continue;
            }

            const Z = Vec4f{ 0.0, 1.0, 0.0, 0.0 };
            const up = if (project.align_to_normal) n else Z;
            const basis = math.quaternion.initFromMat3x3(Mat3x3.initRotationAlign(Z, up));

            const rotation = math.quaternion.initRotationY((2.0 * std.math.pi) * rotation_r);

            const incline_x = math.quaternion.initRotationX(std.math.pi * prototype.incline_jitter[0] * incline_x_r);
            const incline_y = math.quaternion.initRotationZ(std.math.pi * prototype.incline_jitter[1] * incline_z_r);

            const depth_offset = @as(Vec4f, @splat(math.lerp(project.depth_offset_range[0], project.depth_offset_range[1], depth_r))) * up;

            const local_trafo: Transformation = .{
                .position = frag.p + depth_offset,
                .scale = @splat(math.lerp(prototype.scale_range[0], prototype.scale_range[1], scale_r)),
                .rotation = math.quaternion.mul(math.quaternion.mul(math.quaternion.mul(incline_x, incline_y), rotation), basis),
            };

            const trafo = local_trafo.transform(prototype.trafo);

            try instances.append(alloc, .{ .prototype = selected_prototype_id, .transformation = trafo.toMat4x4() });

            if (project.tileable) {
                if (0 == y) {
                    var tile_trafo = trafo;
                    tile_trafo.position[world_axis[1]] += world_extent[1];
                    try instances.append(alloc, .{ .prototype = selected_prototype_id, .transformation = tile_trafo.toMat4x4() });
                } else if (grid[1] - 1 == y) {
                    var tile_trafo = trafo;
                    tile_trafo.position[world_axis[1]] -= world_extent[1];
                    try instances.append(alloc, .{ .prototype = selected_prototype_id, .transformation = tile_trafo.toMat4x4() });
                }

                if (0 == x) {
                    var tile_trafo = trafo;
                    tile_trafo.position[world_axis[0]] += world_extent[0];
                    try instances.append(alloc, .{ .prototype = selected_prototype_id, .transformation = tile_trafo.toMat4x4() });
                } else if (grid[0] - 1 == x) {
                    var tile_trafo = trafo;
                    tile_trafo.position[world_axis[0]] -= world_extent[0];
                    try instances.append(alloc, .{ .prototype = selected_prototype_id, .transformation = tile_trafo.toMat4x4() });
                }
            }
        }
    }
}
