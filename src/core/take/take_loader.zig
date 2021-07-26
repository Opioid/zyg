pub const Take = @import("take.zig").Take;
pub const View = @import("take.zig").View;

const cam = @import("../camera/perspective.zig");
const snsr = @import("../rendering/sensor/sensor.zig");

const Scene = @import("../scene/scene.zig").Scene;

const base = @import("base");
usingnamespace base;
usingnamespace base.math;

const std = @import("std");
const Allocator = std.mem.Allocator;

usingnamespace @import("base");

pub fn load(alloc: *Allocator, scene: *Scene) !Take {
    var take = Take.init();

    var file = try std.fs.cwd().openFile("imrod.take", .{});
    defer file.close();

    const reader = file.reader();

    const buffer = try reader.readAllAlloc(alloc, 100000);
    defer alloc.free(buffer);

    var parser = std.json.Parser.init(alloc, false);
    defer parser.deinit();

    var document = try parser.parse(buffer);
    defer document.deinit();

    const root = document.root;

    var iter = root.Object.iterator();

    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "camera", entry.key_ptr.*)) {
            loadCamera(alloc, &take.view.camera, entry.value_ptr.*, scene);
        } else if (std.mem.eql(u8, "scene", entry.key_ptr.*)) {
            const string = entry.value_ptr.String;
            take.scene_filename = try alloc.alloc(u8, string.len);
            if (take.scene_filename) |filename| {
                std.mem.copy(u8, filename, string);
            }
        }
    }

    return take;
}

fn loadCamera(alloc: *Allocator, camera: *cam.Perspective, value: std.json.Value, scene: *Scene) void {
    var type_value_ptr: ?*std.json.Value = null;

    {
        var iter = value.Object.iterator();

        while (iter.next()) |entry| {
            type_value_ptr = entry.value_ptr;
        }
    }

    if (null == type_value_ptr) {
        return;
    }

    var sensor_value_ptr: ?*std.json.Value = null;

    var trafo = Transformation{
        .position = Vec4f.init1(0.0),
        .scale = Vec4f.init1(1.0),
        .rotation = math.quaternion.identity,
    };

    if (type_value_ptr) |type_value| {
        var iter = type_value.Object.iterator();

        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "parameters", entry.key_ptr.*)) {
                const fov = entry.value_ptr.Object.get("fov") orelse continue;
                camera.fov = math.degreesToRadians(json.readFloat(fov));
            } else if (std.mem.eql(u8, "transformation", entry.key_ptr.*)) {
                json.readTransformation(entry.value_ptr.*, &trafo);
            } else if (std.mem.eql(u8, "sensor", entry.key_ptr.*)) {
                sensor_value_ptr = entry.value_ptr;
            }
        }
    }

    if (sensor_value_ptr) |sensor_value| {
        const resolution = json.readVec2iMember(sensor_value.*, "resolution", math.Vec2i.init1(0));

        camera.resolution = resolution;

        camera.setSensor(loadSensor(sensor_value.*));
    } else {
        return;
    }

    const prop_id = scene.createEntity(alloc);

    scene.propSetWorldTransformation(prop_id, trafo);

    camera.entity = prop_id;
}

fn loadSensor(value: std.json.Value) snsr.Sensor {
    _ = value;

    return snsr.Sensor{ .Unfiltered_opaque = snsr.Unfiltered(snsr.Opaque){} };
}
