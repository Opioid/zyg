const tk = @import("take.zig");
pub const Take = tk.Take;
pub const View = tk.View;

const cam = @import("../camera/perspective.zig");
const snsr = @import("../rendering/sensor/sensor.zig");
const smpl = @import("../sampler/sampler.zig");
const surface = @import("../rendering/integrator/surface/integrator.zig");
const volume = @import("../rendering/integrator/volume/integrator.zig");
const lt = @import("../rendering/integrator/particle/lighttracer.zig");
const LightSampling = @import("../rendering/integrator/helper.zig").LightSampling;
const tm = @import("../rendering/postprocessor/tonemapping/tonemapper.zig");
const Scene = @import("../scene/scene.zig").Scene;
const MaterialBase = @import("../scene/material/material_base.zig").Base;
const Resources = @import("../resource/manager.zig").Manager;
const ReadStream = @import("../file/read_stream.zig").ReadStream;
const PngWriter = @import("../image/encoding/png/writer.zig").Writer;
const RgbeWriter = @import("../image/encoding/rgbe/writer.zig").Writer;
const FFMPEG = @import("../exporting/ffmpeg.zig").FFMPEG;

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

pub fn load(alloc: Allocator, stream: *ReadStream, scene: *Scene, resources: *Resources) !Take {
    _ = resources;

    const buffer = try stream.readAll(alloc);
    defer alloc.free(buffer);

    var parser = std.json.Parser.init(alloc, false);
    defer parser.deinit();

    var document = try parser.parse(buffer);
    defer document.deinit();

    var take = try Take.init(alloc);

    const root = document.root;

    var exporter_value_ptr: ?*std.json.Value = null;
    var integrator_value_ptr: ?*std.json.Value = null;
    var post_value_ptr: ?*std.json.Value = null;
    var sampler_value_ptr: ?*std.json.Value = null;

    var iter = root.Object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "camera", entry.key_ptr.*)) {
            try loadCamera(alloc, &take.view.camera, entry.value_ptr.*, scene);
        } else if (std.mem.eql(u8, "export", entry.key_ptr.*)) {
            exporter_value_ptr = entry.value_ptr;
        } else if (std.mem.eql(u8, "integrator", entry.key_ptr.*)) {
            integrator_value_ptr = entry.value_ptr;
        } else if (std.mem.eql(u8, "post", entry.key_ptr.*)) {
            post_value_ptr = entry.value_ptr;
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

    if (sampler_value_ptr) |sampler_value| {
        take.view.samplers = loadSampler(sampler_value.*, &take.view.num_samples_per_pixel);
    }

    if (post_value_ptr) |post_value| {
        loadPostProcessors(post_value.*, &take.view);
    }

    if (exporter_value_ptr) |exporter_value| {
        take.exporters = try loadExporters(alloc, exporter_value.*, take.view);
    }

    setDefaultIntegrators(&take.view);

    try take.view.configure(alloc);

    return take;
}

fn loadCamera(alloc: Allocator, camera: *cam.Perspective, value: std.json.Value, scene: *Scene) !void {
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

    var param_value_ptr: ?*std.json.Value = null;
    var sensor_value_ptr: ?*std.json.Value = null;

    var trafo = Transformation{
        .position = @splat(4, @as(f32, 0.0)),
        .scale = @splat(4, @as(f32, 1.0)),
        .rotation = math.quaternion.identity,
    };

    if (type_value_ptr) |type_value| {
        var iter = type_value.Object.iterator();
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
        const crop = json.readVec4iMember(sensor_value.*, "crop", Vec4i{ 0, 0, resolution[0], resolution[1] });

        camera.setResolution(resolution, crop);
        camera.sensor = loadSensor(sensor_value.*);
    } else {
        return;
    }

    if (param_value_ptr) |param_value| {
        camera.setParameters(param_value.*);
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
    var clamp = snsr.Clamp{ .Identity = .{} };

    var filter_value_ptr: ?*std.json.Value = null;

    {
        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "alpha_transparency", entry.key_ptr.*)) {
                alpha_transparency = json.readBool(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "clamp", entry.key_ptr.*)) {
                switch (entry.value_ptr.*) {
                    .Array => {
                        const max = json.readVec4f3(entry.value_ptr.*);
                        clamp = snsr.Clamp{ .Max = .{ .max = Vec4f{ max[0], max[1], max[2], 1.0 } } };
                    },
                    else => clamp = snsr.Clamp{ .Luminance = .{ .max = json.readFloat(f32, entry.value_ptr.*) } },
                }
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

                if (alpha_transparency) {
                    if (radius <= 1.0) {
                        return snsr.Sensor{
                            .Filtered_1p0_transparent = snsr.Filtered_1p0_transparent.init(
                                clamp,
                                radius,
                                Blackman{ .r = radius },
                            ),
                        };
                    } else if (radius <= 2.0) {
                        return snsr.Sensor{
                            .Filtered_2p0_transparent = snsr.Filtered_2p0_transparent.init(
                                clamp,
                                radius,
                                Blackman{ .r = radius },
                            ),
                        };
                    }
                } else {
                    if (radius <= 1.0) {
                        return snsr.Sensor{
                            .Filtered_1p0_opaque = snsr.Filtered_1p0_opaque.init(
                                clamp,
                                radius,
                                Blackman{ .r = radius },
                            ),
                        };
                    } else if (radius <= 2.0) {
                        return snsr.Sensor{
                            .Filtered_2p0_opaque = snsr.Filtered_2p0_opaque.init(
                                clamp,
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
        return snsr.Sensor{ .Unfiltered_transparent = .{ .clamp = clamp } };
    }

    return snsr.Sensor{ .Unfiltered_opaque = .{ .clamp = clamp } };
}

fn peekSurfaceIntegrator(value: std.json.Value) bool {
    var niter = value.Object.iterator();
    while (niter.next()) |n| {
        if (std.mem.eql(u8, "surface", n.key_ptr.*)) {
            var siter = n.value_ptr.Object.iterator();
            while (siter.next()) |s| {
                if (std.mem.eql(u8, "AO", s.key_ptr.*)) {
                    return true;
                }
            }
        }
    }

    return false;
}

fn loadIntegrators(value: std.json.Value, view: *View) void {
    if (value.Object.get("particle")) |particle_node| {
        const surface_integrator = peekSurfaceIntegrator(value);

        loadParticleIntegrator(particle_node, view, surface_integrator);
    }

    var iter = value.Object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "surface", entry.key_ptr.*)) {
            loadSurfaceIntegrator(entry.value_ptr.*, view, null != view.lighttracers);
        } else if (std.mem.eql(u8, "volume", entry.key_ptr.*)) {
            loadVolumeIntegrator(entry.value_ptr.*);
        }
    }
}

fn loadSurfaceIntegrator(value: std.json.Value, view: *View, lighttracer: bool) void {
    const Default_min_bounces = 4;
    const Default_max_bounces = 8;

    var light_sampling = LightSampling.Adaptive;

    const Default_caustics = true;

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
            const enable_caustics = json.readBoolMember(entry.value_ptr.*, "caustics", Default_caustics);

            view.surfaces = surface.Factory{ .PT = .{
                .settings = .{
                    .num_samples = num_samples,
                    .min_bounces = min_bounces,
                    .max_bounces = max_bounces,
                    .avoid_caustics = !enable_caustics,
                },
            } };
        } else if (std.mem.eql(u8, "PTDL", entry.key_ptr.*)) {
            const num_samples = json.readUIntMember(entry.value_ptr.*, "num_samples", 1);
            const min_bounces = json.readUIntMember(entry.value_ptr.*, "min_bounces", Default_min_bounces);
            const max_bounces = json.readUIntMember(entry.value_ptr.*, "max_bounces", Default_max_bounces);
            const enable_caustics = json.readBoolMember(entry.value_ptr.*, "caustics", Default_caustics);

            loadLightSampling(entry.value_ptr.*, &light_sampling);

            view.surfaces = surface.Factory{ .PTDL = .{
                .settings = .{
                    .num_samples = num_samples,
                    .min_bounces = min_bounces,
                    .max_bounces = max_bounces,
                    .light_sampling = light_sampling,
                    .avoid_caustics = !enable_caustics,
                },
            } };
        } else if (std.mem.eql(u8, "PTMIS", entry.key_ptr.*)) {
            const num_samples = json.readUIntMember(entry.value_ptr.*, "num_samples", 1);
            const min_bounces = json.readUIntMember(entry.value_ptr.*, "min_bounces", Default_min_bounces);
            const max_bounces = json.readUIntMember(entry.value_ptr.*, "max_bounces", Default_max_bounces);
            const enable_caustics = json.readBoolMember(entry.value_ptr.*, "caustics", Default_caustics) and !lighttracer;

            loadLightSampling(entry.value_ptr.*, &light_sampling);

            view.surfaces = surface.Factory{ .PTMIS = .{
                .settings = .{
                    .num_samples = num_samples,
                    .min_bounces = min_bounces,
                    .max_bounces = max_bounces,
                    .light_sampling = light_sampling,
                    .avoid_caustics = !enable_caustics,
                },
            } };
        }
    }
}

fn loadVolumeIntegrator(value: std.json.Value) void {
    var iter = value.Object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "Tracking", entry.key_ptr.*)) {
            const sr_range = json.readVec2iMember(entry.value_ptr.*, "similarity_relation_range", .{ 16, 64 });
            MaterialBase.setSimilarityRelationRange(@intCast(u32, sr_range[0]), @intCast(u32, sr_range[1]));
        }
    }
}

fn loadParticleIntegrator(value: std.json.Value, view: *View, surface_integrator: bool) void {
    const num_samples = json.readUIntMember(value, "num_samples", 1);
    const max_bounces = json.readUIntMember(value, "max_bounces", 8);
    const full_light_path = json.readBoolMember(value, "full_light_path", !surface_integrator);
    view.num_particles_per_pixel = json.readUIntMember(value, "particles_per_pixel", 1);

    view.lighttracers = lt.Factory{ .settings = .{
        .num_samples = num_samples,
        .min_bounces = 1,
        .max_bounces = max_bounces,
        .full_light_path = full_light_path,
    } };
}

fn setDefaultIntegrators(view: *View) void {
    if (null == view.surfaces and null != view.lighttracers) {
        view.num_samples_per_pixel = 0;
    }

    if (null == view.surfaces) {
        view.surfaces = .{ .AO = .{
            .settings = .{ .num_samples = 1, .radius = 1.0 },
        } };
    }

    if (null == view.volumes) {
        view.volumes = .{ .Multi = .{} };
    }

    if (null == view.lighttracers) {
        view.lighttracers = .{ .settings = .{
            .num_samples = 0,
            .min_bounces = 0,
            .max_bounces = 0,
            .full_light_path = false,
        } };
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
            return .{ .GoldenRatio = {} };
        }
    }

    return .{ .Random = {} };
}

fn loadPostProcessors(value: std.json.Value, view: *View) void {
    for (value.Array.items) |pp| {
        if (pp.Object.iterator().next()) |entry| {
            if (std.mem.eql(u8, "tonemapper", entry.key_ptr.*)) {
                view.pipeline.tonemapper = loadTonemapper(entry.value_ptr.*);
            }
        }
    }
}

fn loadTonemapper(value: std.json.Value) tm.Tonemapper {
    var iter = value.Object.iterator();
    while (iter.next()) |entry| {
        const exposure = json.readFloatMember(entry.value_ptr.*, "exposure", 0.0);

        if (std.mem.eql(u8, "ACES", entry.key_ptr.*)) {
            return .{ .ACES = tm.ACES.init(exposure) };
        }

        if (std.mem.eql(u8, "Linear", entry.key_ptr.*)) {
            return .{ .Linear = tm.Linear.init(exposure) };
        }
    }

    return .{ .Linear = tm.Linear.init(0.0) };
}

fn loadLightSampling(value: std.json.Value, sampling: *LightSampling) void {
    const light_sampling_node = value.Object.get("light_sampling") orelse return;

    var iter = light_sampling_node.Object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "strategy", entry.key_ptr.*)) {
            const strategy = entry.value_ptr.String;

            if (std.mem.eql(u8, "Single", strategy)) {
                sampling.* = .Single;
            } else if (std.mem.eql(u8, "Single", strategy)) {
                sampling.* = .Adaptive;
            }
        } else if (std.mem.eql(u8, "splitting_threshold", entry.key_ptr.*)) {}
    }
}

fn loadExporters(alloc: Allocator, value: std.json.Value, view: View) !tk.Exporters {
    var exporters = tk.Exporters{};

    var iter = value.Object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "Image", entry.key_ptr.*)) {
            const format = json.readStringMember(entry.value_ptr.*, "format", "PNG");

            const alpha = view.camera.sensor.alphaTransparency();

            if (std.mem.eql(u8, "RGBE", format)) {
                try exporters.append(alloc, .{ .ImageSequence = .{
                    .writer = .{ .RGBE = .{} },
                } });
            } else {
                const error_diffusion = json.readBoolMember(entry.value_ptr.*, "error_diffusion", false);

                try exporters.append(alloc, .{ .ImageSequence = .{
                    .writer = .{ .PNG = PngWriter.init(error_diffusion, alpha) },
                } });
            }
        } else if (std.mem.eql(u8, "Movie", entry.key_ptr.*)) {
            var framerate = json.readUIntMember(entry.value_ptr.*, "framerate", 0);
            if (0 == framerate) {
                framerate = @floatToInt(u32, @round(1.0 / @intToFloat(f64, view.camera.frame_step)));
            }

            const error_diffusion = json.readBoolMember(entry.value_ptr.*, "error_diffusion", false);

            try exporters.append(alloc, .{ .FFMPEG = try FFMPEG.init(
                alloc,
                view.camera.sensorDimensions(),
                framerate,
                error_diffusion,
            ) });
        }
    }

    return exporters;
}
