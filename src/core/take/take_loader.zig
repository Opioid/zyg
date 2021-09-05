const tk = @import("take.zig");
pub const Take = tk.Take;
pub const View = tk.View;

const cam = @import("../camera/perspective.zig");
const snsr = @import("../rendering/sensor/sensor.zig");
const smpl = @import("../sampler/sampler.zig");
const surface = @import("../rendering/integrator/surface/integrator.zig");
const Scene = @import("../scene/scene.zig").Scene;
const Resources = @import("../resource/manager.zig").Manager;
const ReadStream = @import("../file/read_stream.zig").ReadStream;

const base = @import("base");
usingnamespace base;
usingnamespace base.math;

const std = @import("std");
const Allocator = std.mem.Allocator;

usingnamespace @import("base");

const Error = error{
    NoScene,
};

pub fn load(alloc: *Allocator, stream: *ReadStream, scene: *Scene, resources: *Resources) !Take {
    _ = resources;

    const buffer = try stream.reader.unbuffered_reader.readAllAlloc(alloc, std.math.maxInt(u64));
    defer alloc.free(buffer);

    var parser = std.json.Parser.init(alloc, false);
    defer parser.deinit();

    var document = try parser.parse(buffer);
    defer document.deinit();

    var take = Take.init();

    const root = document.root;

    var integrator_value_ptr: ?*std.json.Value = null;
    var sampler_value_ptr: ?*std.json.Value = null;

    var iter = root.Object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "camera", entry.key_ptr.*)) {
            try loadCamera(alloc, &take.view.camera, entry.value_ptr.*, scene);
        } else if (std.mem.eql(u8, "integrator", entry.key_ptr.*)) {
            integrator_value_ptr = entry.value_ptr;
        } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
            sampler_value_ptr = entry.value_ptr;
        } else if (std.mem.eql(u8, "scene", entry.key_ptr.*)) {
            const string = entry.value_ptr.String;
            take.scene_filename = try alloc.alloc(u8, string.len);
            std.mem.copy(u8, take.scene_filename, string);
        }
    }

    if (0 == take.scene_filename.len) {
        return Error.NoScene;
    }

    if (integrator_value_ptr) |integrator_value| {
        loadIntegrators(integrator_value.*, &take.view);
    }

    if (surface.Factory.Invalid == take.view.surfaces) {
        take.view.surfaces = surface.Factory{ .AO = .{
            .settings = .{ .num_samples = 1, .radius = 1.0 },
        } };
    }

    if (sampler_value_ptr) |sampler_value| {
        take.view.samplers = loadSampler(sampler_value.*, &take.view.num_samples_per_pixel);
    }

    return take;
}

fn loadCamera(alloc: *Allocator, camera: *cam.Perspective, value: std.json.Value, scene: *Scene) !void {
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
        const resolution = json.readVec2iMember(sensor_value.*, "resolution", Vec2i.init1(0));
        const crop = json.readVec4iMember(sensor_value.*, "crop", Vec4i.init2_2(Vec2i.init1(0), resolution));

        camera.setResolution(resolution, crop);

        camera.setSensor(loadSensor(sensor_value.*));
    } else {
        return;
    }

    const prop_id = try scene.createEntity(alloc);

    scene.propSetWorldTransformation(prop_id, trafo);

    camera.entity = prop_id;
}

fn identity(x: f32) f32 {
    return x;
}

const Blackman = struct {
    r: f32,

    pub fn eval(self: Blackman, x: f32) f32 {
        const a0 = 0.35875;
        const a1 = 0.48829;
        const a2 = 0.14128;
        const a3 = 0.01168;

        const b = (std.math.pi * (x + self.r)) / self.r;

        return a0 - a1 * @cos(b) + a2 * @cos(2.0 * b) - a3 * @cos(3.0 * b);
    }
};

fn loadSensor(value: std.json.Value) snsr.Sensor {
    var alpha_transparency = false;

    var filter_value_ptr: ?*std.json.Value = null;

    {
        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "alpha_transparency", entry.key_ptr.*)) {
                alpha_transparency = json.readBool(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "filter", entry.key_ptr.*)) {
                filter_value_ptr = entry.value_ptr;
            }
        }
    }

    if (filter_value_ptr) |filter_value| {
        var iter = filter_value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "Gaussian", entry.key_ptr.*) or
                std.mem.eql(u8, "Blackman", entry.key_ptr.*) or
                std.mem.eql(u8, "Mitchell", entry.key_ptr.*))
            {
                const radius = json.readFloatMember(entry.value_ptr.*, "radius", 2.0);

                if (alpha_transparency) {} else {
                    if (radius <= 1.0) {
                        return snsr.Sensor{
                            .Filtered_1p0_opaque = snsr.Filtered_1p0_opaque.init(
                                radius,
                                Blackman{ .r = radius },
                            ),
                        };
                    } else if (radius <= 2.0) {
                        return snsr.Sensor{
                            .Filtered_2p0_opaque = snsr.Filtered_2p0_opaque.init(
                                radius,
                                Blackman{ .r = radius },
                            ),
                        };
                    }
                }
            }
        }
    }

    if (alpha_transparency) {
        return snsr.Sensor{ .Unfiltered_transparent = .{} };
    }

    return snsr.Sensor{ .Unfiltered_opaque = .{} };
}

fn loadIntegrators(value: std.json.Value, view: *View) void {
    var iter = value.Object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "surface", entry.key_ptr.*)) {
            loadSurfaceIntegrator(entry.value_ptr.*, view);
        }
    }
}

fn loadSurfaceIntegrator(value: std.json.Value, view: *View) void {
    const Default_min_bounces = 4;
    const Default_max_bounces = 8;

    var iter = value.Object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "AO", entry.key_ptr.*)) {
            const num_samples = json.readUIntMember(entry.value_ptr.*, "num_samples", 1);

            const radius = json.readFloatMember(entry.value_ptr.*, "radius", 1.0);

            view.surfaces = surface.Factory{ .AO = .{
                .settings = .{ .num_samples = num_samples, .radius = radius },
            } };
        } else if (std.mem.eql(u8, "PT", entry.key_ptr.*)) {
            const num_samples = json.readUIntMember(entry.value_ptr.*, "num_samples", 1);

            const min_bounces = json.readUIntMember(entry.value_ptr.*, "min_bounces", Default_min_bounces);
            const max_bounces = json.readUIntMember(entry.value_ptr.*, "max_bounces", Default_max_bounces);

            view.surfaces = surface.Factory{ .PT = .{
                .settings = .{
                    .num_samples = num_samples,
                    .min_bounces = min_bounces,
                    .max_bounces = max_bounces,
                },
            } };
        }
    }
}

fn loadSampler(value: std.json.Value, num_samples_per_pixel: *u32) smpl.Factory {
    var iter = value.Object.iterator();
    while (iter.next()) |entry| {
        num_samples_per_pixel.* = json.readUIntMember(entry.value_ptr.*, "samples_per_pixel", 1);

        if (std.mem.eql(u8, "Random", entry.key_ptr.*)) {
            return .{ .Random = {} };
        }

        if (std.mem.eql(u8, "Golden_ratio", entry.key_ptr.*)) {
            return .{ .Golden_ratio = {} };
        }
    }

    return .{ .Random = {} };
}
