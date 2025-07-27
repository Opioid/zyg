const Graph = @import("util").SceneGraph;

const core = @import("core");
const cam = core.camera;
const View = core.take.View;
const Prop = core.scene.Prop;
const Sensor = core.rendering.Sensor;
const Tonemapper = Sensor.Tonemapper;
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

pub fn load(alloc: Allocator, stream: ReadStream, graph: *Graph, resources: *Resources) !void {
    const buffer = try stream.readAll(alloc);
    defer alloc.free(buffer);

    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        alloc,
        buffer,
        .{ .duplicate_field_behavior = .use_last },
    );
    defer parsed.deinit();

    const root = parsed.value;

    if (root.object.get("scene")) |scene_filename| {
        graph.take.scene_filename = try alloc.dupe(u8, scene_filename.string);
    }

    if (0 == graph.take.scene_filename.len) {
        return Error.NoScene;
    }

    var exporter_value_ptr: ?*std.json.Value = null;
    var integrator_value_ptr: ?*std.json.Value = null;
    var post_value_ptr: ?*std.json.Value = null;

    var iter = root.object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "aov", entry.key_ptr.*)) {
            graph.take.view.loadAOV(entry.value_ptr.*);
        } else if (std.mem.eql(u8, "sensor", entry.key_ptr.*)) {
            graph.take.view.sensor.deinit(alloc);
            graph.take.view.sensor = loadSensor(entry.value_ptr.*);
        } else if (std.mem.eql(u8, "camera", entry.key_ptr.*)) {
            try loadCamera(alloc, entry.value_ptr.*, graph, resources);
        } else if (std.mem.eql(u8, "cameras", entry.key_ptr.*)) {
            for (entry.value_ptr.array.items) |cn| {
                try loadCamera(alloc, cn, graph, resources);
            }
        } else if (std.mem.eql(u8, "export", entry.key_ptr.*)) {
            exporter_value_ptr = entry.value_ptr;
        } else if (std.mem.eql(u8, "integrator", entry.key_ptr.*)) {
            integrator_value_ptr = entry.value_ptr;
        } else if (std.mem.eql(u8, "post", entry.key_ptr.*)) {
            post_value_ptr = entry.value_ptr;
        } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
            loadSampler(entry.value_ptr.*, &graph.take.view);
        }
    }

    if (integrator_value_ptr) |integrator_value| {
        graph.take.view.loadIntegrators(integrator_value.*);
    }

    if (post_value_ptr) |post_value| {
        loadPostProcessors(post_value.*, &graph.take.view);
    }

    if (exporter_value_ptr) |exporter_value| {
        try graph.take.loadExporters(alloc, exporter_value.*);
    }

    graph.take.view.configure();
}

fn loadCamera(alloc: Allocator, value: std.json.Value, graph: *Graph, resources: *Resources) !void {
    const parent_trafo: Transformation = .identity;

    var cam_value_ptr: ?*std.json.Value = null;

    var cam_iter = value.object.iterator();
    while (cam_iter.next()) |cam_entry| {
        if (std.mem.eql(u8, "Orthographic", cam_entry.key_ptr.*)) {
            var camera = cam.Orthographic{};

            if (cam_entry.value_ptr.object.get("parameters")) |parameters| {
                camera.setParameters(parameters);
            }

            cam_value_ptr = cam_entry.value_ptr;

            try graph.take.view.cameras.append(alloc, .{ .Orthographic = camera });

            break;
        } else if (std.mem.eql(u8, "Perspective", cam_entry.key_ptr.*)) {
            var camera = cam.Perspective{};

            if (cam_entry.value_ptr.object.get("parameters")) |parameters| {
                try camera.setParameters(alloc, parameters, &graph.scene, resources);
            }

            cam_value_ptr = cam_entry.value_ptr;

            try graph.take.view.cameras.append(alloc, .{ .Perspective = camera });

            break;
        }
    }

    if (cam_value_ptr) |cam_value| {
        const num_cameras = graph.take.view.cameras.items.len;
        var camera = graph.take.view.cameras.items[num_cameras - 1].super();

        if (cam_value.object.get("shutter")) |shutter_value| {
            loadShutter(shutter_value, camera);
        }

        graph.scene.calculateNumInterpolationFrames(camera.frame_step, camera.frame_duration);

        const entity_id = try graph.scene.createEntity(alloc);
        camera.entity = entity_id;

        var trafo: Transformation = .identity;
        if (cam_value.object.get("transformation")) |trafo_value| {
            json.readTransformation(trafo_value, &trafo);
        }

        _ = try graph.propSetTransformation(
            alloc,
            entity_id,
            Prop.Null,
            trafo,
            parent_trafo,
            cam_value.object.get("animation"),
            false,
        );

        const resolution = json.readVec2iMember(cam_value.*, "resolution", .{ 0, 0 });
        const crop = json.readVec4iMember(cam_value.*, "crop", .{ 0, 0, resolution[0], resolution[1] });

        camera.setResolution(resolution, crop);

        try graph.camera_trafos.append(alloc, trafo);
    }
}

fn loadShutter(value: std.json.Value, camera: *cam.Base) void {
    var motion_blur = true;

    var open: f32 = 0.0;
    var close: f32 = 1.0;

    var slope_buffer: [8]f32 = undefined;
    var slope: []f32 = &.{};

    var iter = value.object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "frame_step", entry.key_ptr.*)) {
            camera.frame_step = core.scene.Scene.absoluteTime(json.readFloat(f64, entry.value_ptr.*));
        } else if (std.mem.eql(u8, "frames_per_second", entry.key_ptr.*)) {
            const fps = json.readFloat(f64, entry.value_ptr.*);
            if (0.0 == fps) {
                camera.frame_step = 0;
            } else {
                camera.frame_step = @intFromFloat(@round(@as(f64, @floatFromInt(core.scene.Scene.UnitsPerSecond)) / fps));
            }
        } else if (std.mem.eql(u8, "open", entry.key_ptr.*)) {
            open = json.readFloat(f32, entry.value_ptr.*);
        } else if (std.mem.eql(u8, "close", entry.key_ptr.*)) {
            close = json.readFloat(f32, entry.value_ptr.*);
        } else if (std.mem.eql(u8, "slope", entry.key_ptr.*)) {
            const num_elem = @min(slope_buffer.len, entry.value_ptr.array.items.len);
            for (0..num_elem) |i| {
                slope_buffer[i] = json.readFloat(f32, entry.value_ptr.array.items[i]);
            }
            slope = slope_buffer[0..num_elem];
        } else if (std.mem.eql(u8, "motion_blur", entry.key_ptr.*)) {
            motion_blur = json.readBool(entry.value_ptr.*);
        }
    }

    camera.setShutter(open, close, slope);

    camera.frame_duration = if (motion_blur) camera.frame_step else 0;
}

fn loadSensor(value: std.json.Value) Sensor {
    const alpha_transparency = json.readBoolMember(value, "alpha_transparency", false);

    const class: Sensor.Buffer.Class = if (alpha_transparency) .Transparent else .Opaque;

    var clamp_max: Sensor.Clamp = .infinite;
    if (value.object.get("clamp")) |clamp_node| {
        switch (clamp_node) {
            .object => {
                clamp_max.direct = json.readFloatMember(clamp_node, "direct", clamp_max.direct);
                clamp_max.indirect = json.readFloatMember(clamp_node, "indirect", clamp_max.indirect);
            },
            else => {},
        }
    }

    if (value.object.get("filter")) |filter_node| {
        const radius: f32 = 2.0;

        var iter = filter_node.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "Blackman", entry.key_ptr.*)) {
                const filter = Sensor.Blackman{ .r = radius };

                return Sensor.init(class, clamp_max, radius, filter);
            } else if (std.mem.eql(u8, "Mitchell", entry.key_ptr.*)) {
                const filter = Sensor.Mitchell{ .b = 1.0 / 3.0, .c = 1.0 / 3.0 };

                return Sensor.init(class, clamp_max, radius, filter);
            }
        }
    }

    const filter = Sensor.Blackman{ .r = 0.0 };

    return Sensor.init(class, clamp_max, 0.0, filter);
}

fn loadSampler(value: std.json.Value, view: *View) void {
    var iter = value.object.iterator();
    while (iter.next()) |entry| {
        const num_samples = json.readUIntMember(entry.value_ptr.*, "samples_per_pixel", 1);
        const noise_threshold = json.readFloatMember(entry.value_ptr.*, "noise_threshold", 0.02);

        view.num_samples_per_pixel = num_samples;
        view.qm_threshold = noise_threshold;

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
                view.sensor.tonemapper = loadTonemapper(entry.value_ptr.*);
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

        if (std.mem.eql(u8, "PbrNeutral", entry.key_ptr.*)) {
            return Tonemapper.init(.PbrNeutral, exposure);
        }
    }

    return Tonemapper.init(.Linear, 0.0);
}
