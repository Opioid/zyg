const Graph = @import("scene_graph.zig").Graph;

const core = @import("core");
const tk = core.tk;
const Take = tk.Take;
const View = tk.View;
const cam = core.camera;
const snsr = core.rendering.snsr;
const Tonemapper = snsr.Tonemapper;
const ReadStream = core.file.ReadStream;
const Resources = core.resource.Manager;

const base = @import("base");
const json = base.json;
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Transformation = math.Transformation;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    NoScene,
};

pub fn load(alloc: Allocator, stream: ReadStream, take: *Take, graph: *Graph, resources: *Resources) !void {
    const buffer = try stream.readAll(alloc);
    defer alloc.free(buffer);

    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, buffer, .{});
    defer parsed.deinit();

    const root = parsed.value;

    if (root.object.get("scene")) |scene_filename| {
        take.scene_filename = try alloc.dupe(u8, scene_filename.string);
    }

    if (0 == take.scene_filename.len) {
        return Error.NoScene;
    }

    var exporter_value_ptr: ?*std.json.Value = null;
    var integrator_value_ptr: ?*std.json.Value = null;
    var post_value_ptr: ?*std.json.Value = null;

    var iter = root.object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "aov", entry.key_ptr.*)) {
            take.view.loadAOV(entry.value_ptr.*);
        } else if (std.mem.eql(u8, "camera", entry.key_ptr.*)) {
            try loadCamera(alloc, &take.view.camera, entry.value_ptr.*, graph, resources);
        } else if (std.mem.eql(u8, "export", entry.key_ptr.*)) {
            exporter_value_ptr = entry.value_ptr;
        } else if (std.mem.eql(u8, "integrator", entry.key_ptr.*)) {
            integrator_value_ptr = entry.value_ptr;
        } else if (std.mem.eql(u8, "post", entry.key_ptr.*)) {
            post_value_ptr = entry.value_ptr;
        } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
            loadSampler(entry.value_ptr.*, &take.view);
        }
    }

    if (integrator_value_ptr) |integrator_value| {
        take.view.loadIntegrators(integrator_value.*);
    }

    if (post_value_ptr) |post_value| {
        loadPostProcessors(post_value.*, &take.view);
    }

    if (exporter_value_ptr) |exporter_value| {
        try take.loadExporters(alloc, exporter_value.*);
    }

    take.view.configure();
}

pub fn loadCameraTransformation(alloc: Allocator, stream: ReadStream, camera: *cam.Perspective, graph: *Graph) !void {
    const buffer = try stream.readAll(alloc);
    defer alloc.free(buffer);

    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, buffer, .{});
    defer parsed.deinit();

    const root = parsed.value;

    if (root.object.get("camera")) |camera_node| {
        var iter = camera_node.object.iterator();
        if (iter.next()) |type_value| {
            var trafo = Transformation{
                .position = @splat(0.0),
                .scale = @splat(1.0),
                .rotation = math.quaternion.identity,
            };

            if (type_value.value_ptr.object.get("transformation")) |trafo_node| {
                json.readTransformation(trafo_node, &trafo);
            }

            const prop_id = try graph.scene.createEntity(alloc);
            graph.scene.propSetWorldTransformation(prop_id, trafo);
            //_ = try graph.createEntity(alloc, prop_id);
            camera.entity = prop_id;
        }
    }
}

fn loadCamera(alloc: Allocator, camera: *cam.Perspective, value: std.json.Value, graph: *Graph, resources: *Resources) !void {
    var type_value_ptr: ?*std.json.Value = null;

    {
        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            type_value_ptr = entry.value_ptr;
        }
    }

    if (null == type_value_ptr) {
        return;
    }

    var param_value_ptr: ?*std.json.Value = null;
    var sensor_value_ptr: ?*std.json.Value = null;

    var trafo = Transformation{
        .position = @splat(0.0),
        .scale = @splat(1.0),
        .rotation = math.quaternion.identity,
    };

    if (type_value_ptr) |type_value| {
        var iter = type_value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "parameters", entry.key_ptr.*)) {
                param_value_ptr = entry.value_ptr;
            } else if (std.mem.eql(u8, "transformation", entry.key_ptr.*)) {
                json.readTransformation(entry.value_ptr.*, &trafo);
            } else if (std.mem.eql(u8, "sensor", entry.key_ptr.*)) {
                sensor_value_ptr = entry.value_ptr;
            }
        }
    }

    if (sensor_value_ptr) |sensor_value| {
        const resolution = json.readVec2iMember(sensor_value.*, "resolution", .{ 0, 0 });
        const crop = json.readVec4iMember(sensor_value.*, "crop", .{ 0, 0, resolution[0], resolution[1] });

        camera.setResolution(resolution, crop);
        camera.sensor.deinit(alloc);
        camera.sensor = loadSensor(sensor_value.*);
    } else {
        return;
    }

    if (param_value_ptr) |param_value| {
        try camera.setParameters(alloc, param_value.*, &graph.scene, resources);
    }

    const prop_id = try graph.scene.createEntity(alloc);
    graph.scene.propSetWorldTransformation(prop_id, trafo);
    // _ = try graph.createEntity(alloc, prop_id);
    camera.entity = prop_id;
}

fn loadSensor(value: std.json.Value) snsr.Sensor {
    var alpha_transparency = false;
    var clamp_max: f32 = std.math.floatMax(f32);

    var filter_value_ptr: ?*std.json.Value = null;

    {
        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "alpha_transparency", entry.key_ptr.*)) {
                alpha_transparency = json.readBool(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "clamp", entry.key_ptr.*)) {
                switch (entry.value_ptr.*) {
                    .array => |a| clamp_max = json.readFloat(f32, a.items[0]),
                    else => clamp_max = json.readFloat(f32, entry.value_ptr.*),
                }
            } else if (std.mem.eql(u8, "filter", entry.key_ptr.*)) {
                filter_value_ptr = entry.value_ptr;
            }
        }
    }

    if (filter_value_ptr) |filter_value| {
        const radius: f32 = 2.0;

        var iter = filter_value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "Blackman", entry.key_ptr.*)) {
                const filter = snsr.Blackman{ .r = radius };

                if (alpha_transparency) {
                    return snsr.Sensor.init(.{ .Transparent = .{} }, clamp_max, radius, filter);
                } else {
                    return snsr.Sensor.init(.{ .Opaque = .{} }, clamp_max, radius, filter);
                }
            } else if (std.mem.eql(u8, "Mitchell", entry.key_ptr.*)) {
                const filter = snsr.Mitchell{ .b = 1.0 / 3.0, .c = 1.0 / 3.0 };

                if (alpha_transparency) {
                    return snsr.Sensor.init(.{ .Transparent = .{} }, clamp_max, radius, filter);
                } else {
                    return snsr.Sensor.init(.{ .Opaque = .{} }, clamp_max, radius, filter);
                }
            }
        }
    }

    const filter = snsr.Blackman{ .r = 0.0 };

    if (alpha_transparency) {
        return snsr.Sensor.init(.{ .Transparent = .{} }, clamp_max, 0.0, filter);
    }

    return snsr.Sensor.init(.{ .Opaque = .{} }, clamp_max, 0.0, filter);
}

fn loadSampler(value: std.json.Value, view: *View) void {
    var iter = value.object.iterator();
    while (iter.next()) |entry| {
        const num_samples = json.readUIntMember(entry.value_ptr.*, "samples_per_pixel", 1);
        const quality = json.readFloatMember(entry.value_ptr.*, "quality", 1.0);

        if (quality <= 0.0) {
            view.num_samples_per_pixel = 1;
            view.qm_threshold = 0.0;
        } else {
            view.num_samples_per_pixel = num_samples;
            view.qm_threshold = @abs(1.0 - (1.0 / @sqrt(quality)));
        }

        if (std.mem.eql(u8, "Random", entry.key_ptr.*)) {
            view.samplers = .{ .Random = {} };
            return;
        }
    }

    view.samplers = .{ .Sobol = {} };
}

fn loadPostProcessors(value: std.json.Value, view: *View) void {
    for (value.array.items) |pp| {
        var iter = pp.object.iterator();
        if (iter.next()) |entry| {
            if (std.mem.eql(u8, "tonemapper", entry.key_ptr.*)) {
                view.camera.sensor.tonemapper = loadTonemapper(entry.value_ptr.*);
            }
        }
    }
}

fn loadTonemapper(value: std.json.Value) Tonemapper {
    var iter = value.object.iterator();
    while (iter.next()) |entry| {
        const exposure = json.readFloatMember(entry.value_ptr.*, "exposure", 0.0);

        if (std.mem.eql(u8, "ACES", entry.key_ptr.*)) {
            return Tonemapper.init(.ACES, exposure);
        }

        if (std.mem.eql(u8, "AgX", entry.key_ptr.*)) {
            return Tonemapper.init(.{ .AgX = .Substitute }, exposure);
        }

        if (std.mem.eql(u8, "Linear", entry.key_ptr.*)) {
            return Tonemapper.init(.Linear, exposure);
        }
    }

    return Tonemapper.init(.Linear, 0.0);
}
