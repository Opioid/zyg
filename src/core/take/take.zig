const aov = @import("../rendering/sensor/aov/aov_value.zig");
const snsr = @import("../rendering/sensor/sensor.zig");
const Sensor = snsr.Sensor;
const surface = @import("../rendering/integrator/surface/integrator.zig");
const Lighttracer = @import("../rendering/integrator/particle/lighttracer.zig").Lighttracer;
const hlp = @import("../rendering/integrator/helper.zig");
const LightSampling = hlp.LightSampling;
const CausticsPath = hlp.CausticsPath;
const CausticsResolve = @import("../scene/renderstate.zig").CausticsResolve;
const LightTree = @import("../scene/light/light_tree.zig");
const SamplerFactory = @import("../sampler/sampler.zig").Factory;
const cam = @import("../camera/perspective.zig");
const Sink = @import("../exporting/sink.zig").Sink;
const MaterialBase = @import("../scene/material/material_base.zig").Base;
const PngWriter = @import("../image/encoding/png/png_writer.zig").Writer;
const FFMPEG = @import("../exporting/ffmpeg.zig").FFMPEG;

const base = @import("base");
const json = base.json;
const math = base.math;
const Vec2i = math.Vec2i;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub const Exporters = List(Sink);

pub const PhotonSettings = struct {
    num_photons: u32 = 0,
    max_bounces: u32 = 2,

    iteration_threshold: f32 = 0.0,
    search_radius: f32 = 0.01,
    merge_radius: f32 = 0.0025,
    coarse_search_radius: f32 = 0.1,

    full_light_path: bool = false,
};

pub const View = struct {
    samplers: SamplerFactory = .{ .Sobol = {} },

    surface_integrator: surface.Integrator = .{ .AOV = .{
        .settings = .{
            .value = .AO,
            .num_samples = 1,
            .max_bounces = 1,
            .radius = 1.0,
            .photons_not_only_through_specular = false,
        },
    } },

    lighttracer: Lighttracer = .{ .settings = .{
        .min_bounces = 0,
        .max_bounces = 0,
        .full_light_path = false,
    } },

    sensor: Sensor = Sensor.init(
        .{ .Opaque = .{} },
        std.math.floatMax(f32),
        2.0,
        snsr.Mitchell{ .b = 1.0 / 3.0, .c = 1.0 / 3.0 },
    ),

    aovs: aov.Factory = .{},

    cameras: List(cam.Perspective) = .{},

    num_samples_per_pixel: u32 = 0,
    num_particles_per_pixel: u32 = 0,
    qm_threshold: f32 = 0.0,
    aov_sample_count: bool = false,

    photon_settings: PhotonSettings = .{},

    pub const AovValue = aov.Value;

    const Default_min_bounces = 4;
    const Default_max_bounces = 16;

    pub fn deinit(self: *View, alloc: Allocator) void {
        self.sensor.deinit(alloc);

        for (self.cameras.items) |*c| {
            c.deinit(alloc);
        }

        self.cameras.deinit(alloc);
    }

    pub fn clear(self: *View, alloc: Allocator) void {
        for (self.cameras.items) |*c| {
            c.deinit(alloc);
        }

        self.cameras.clearRetainingCapacity();
    }

    pub fn configure(self: *View) void {
        const spp = if (self.num_samples_per_pixel > 0) self.num_samples_per_pixel else self.num_particles_per_pixel;
        const spacing = 1.0 / @sqrt(@as(f32, @floatFromInt(spp)));

        for (self.cameras.items) |*c| {
            c.sample_spacing = spacing;
        }
    }

    pub fn loadAOV(self: *View, value: std.json.Value) void {
        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "Albedo", entry.key_ptr.*)) {
                self.aovs.set(.Albedo, json.readBool(entry.value_ptr.*));
            } else if (std.mem.eql(u8, "Depth", entry.key_ptr.*)) {
                self.aovs.set(.Depth, json.readBool(entry.value_ptr.*));
            } else if (std.mem.eql(u8, "Material_id", entry.key_ptr.*)) {
                self.aovs.set(.MaterialId, json.readBool(entry.value_ptr.*));
            } else if (std.mem.eql(u8, "Geometric_normal", entry.key_ptr.*)) {
                self.aovs.set(.GeometricNormal, json.readBool(entry.value_ptr.*));
            } else if (std.mem.eql(u8, "Shading_normal", entry.key_ptr.*)) {
                self.aovs.set(.ShadingNormal, json.readBool(entry.value_ptr.*));
            } else if (std.mem.eql(u8, "Sample_count", entry.key_ptr.*)) {
                self.aov_sample_count = json.readBool(entry.value_ptr.*);
            }
        }
    }

    pub fn loadIntegrators(self: *View, value: std.json.Value) void {
        if (value.object.get("particle")) |particle_node| {
            self.loadParticleIntegrator(particle_node, self.num_samples_per_pixel > 0);
        }

        const lighttracer = self.num_particles_per_pixel > 0;

        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "surface", entry.key_ptr.*)) {
                self.loadSurfaceIntegrator(entry.value_ptr.*, lighttracer);
            } else if (std.mem.eql(u8, "photon", entry.key_ptr.*)) {
                self.photon_settings = loadPhotonSettings(entry.value_ptr.*, lighttracer);
            }
        }
    }

    fn loadSurfaceIntegrator(self: *View, value: std.json.Value, lighttracer: bool) void {
        var light_sampling = LightSampling.Adaptive;

        const Default_caustics_resolve = CausticsResolve.Full;

        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "AOV", entry.key_ptr.*)) {
                const value_name = json.readStringMember(entry.value_ptr.*, "value", "");
                var value_type: surface.AOV.Value = .AO;

                if (std.mem.eql(u8, "Tangent", value_name)) {
                    value_type = .Tangent;
                } else if (std.mem.eql(u8, "Bitangent", value_name)) {
                    value_type = .Bitangent;
                } else if (std.mem.eql(u8, "Geometric_normal", value_name)) {
                    value_type = .GeometricNormal;
                } else if (std.mem.eql(u8, "Shading_normal", value_name)) {
                    value_type = .ShadingNormal;
                } else if (std.mem.eql(u8, "Light_sample_count", value_name)) {
                    value_type = .LightSampleCount;
                } else if (std.mem.eql(u8, "Side", value_name)) {
                    value_type = .Side;
                } else if (std.mem.eql(u8, "Photons", value_name)) {
                    value_type = .Photons;
                }

                const num_samples = json.readUIntMember(entry.value_ptr.*, "num_samples", 1);
                const max_bounces = json.readUIntMember(entry.value_ptr.*, "max_bounces", Default_max_bounces);
                const radius = json.readFloatMember(entry.value_ptr.*, "radius", 1.0);

                loadLightSampling(entry.value_ptr.*, &light_sampling);

                self.surface_integrator = .{ .AOV = .{
                    .settings = .{
                        .value = value_type,
                        .num_samples = num_samples,
                        .max_bounces = max_bounces,
                        .radius = radius,
                        .photons_not_only_through_specular = !lighttracer,
                    },
                } };
            } else if (std.mem.eql(u8, "PT", entry.key_ptr.*)) {
                const min_bounces = json.readUIntMember(entry.value_ptr.*, "min_bounces", Default_min_bounces);
                const max_bounces = json.readUIntMember(entry.value_ptr.*, "max_bounces", Default_max_bounces);
                const caustics_resolve = readCausticsResolve(entry.value_ptr.*, Default_caustics_resolve);

                self.surface_integrator = .{ .PT = .{
                    .settings = .{
                        .min_bounces = min_bounces,
                        .max_bounces = max_bounces,
                        .caustics_path = .Off != caustics_resolve,
                        .caustics_resolve = caustics_resolve,
                    },
                } };
            } else if (std.mem.eql(u8, "PTDL", entry.key_ptr.*)) {
                const min_bounces = json.readUIntMember(entry.value_ptr.*, "min_bounces", Default_min_bounces);
                const max_bounces = json.readUIntMember(entry.value_ptr.*, "max_bounces", Default_max_bounces);
                const caustics_resolve = readCausticsResolve(entry.value_ptr.*, Default_caustics_resolve);

                loadLightSampling(entry.value_ptr.*, &light_sampling);

                self.surface_integrator = .{ .PTDL = .{
                    .settings = .{
                        .min_bounces = min_bounces,
                        .max_bounces = max_bounces,
                        .light_sampling = light_sampling,
                        .caustics_path = .Off != caustics_resolve,
                        .caustics_resolve = caustics_resolve,
                    },
                } };
            } else if (std.mem.eql(u8, "PTMIS", entry.key_ptr.*)) {
                const min_bounces = json.readUIntMember(entry.value_ptr.*, "min_bounces", Default_min_bounces);
                const max_bounces = json.readUIntMember(entry.value_ptr.*, "max_bounces", Default_max_bounces);
                const caustics_resolve = readCausticsResolve(entry.value_ptr.*, Default_caustics_resolve);

                loadLightSampling(entry.value_ptr.*, &light_sampling);

                var caustics_path = false;
                if (.Off != caustics_resolve) {
                    caustics_path = if (lighttracer) false else true;
                }

                self.surface_integrator = .{ .PTMIS = .{
                    .settings = .{
                        .min_bounces = min_bounces,
                        .max_bounces = max_bounces,
                        .light_sampling = light_sampling,
                        .caustics_path = caustics_path,
                        .caustics_resolve = caustics_resolve,
                        .photons_not_only_through_specular = !lighttracer,
                    },
                } };
            }
        }
    }

    fn loadVolumeIntegrator(value: std.json.Value) void {
        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "Tracking", entry.key_ptr.*)) {
                const sr_range = json.readVec2iMember(entry.value_ptr.*, "similarity_relation_range", .{ 16, 64 });
                MaterialBase.setSimilarityRelationRange(@as(u32, @intCast(sr_range[0])), @as(u32, @intCast(sr_range[1])));
            }
        }
    }

    fn loadParticleIntegrator(self: *View, value: std.json.Value, surface_integrator: bool) void {
        const min_bounces = json.readUIntMember(value, "min_bounces", Default_min_bounces);
        const max_bounces = json.readUIntMember(value, "max_bounces", Default_max_bounces);
        const full_light_path = json.readBoolMember(value, "full_light_path", true);
        self.num_particles_per_pixel = json.readUIntMember(value, "particles_per_pixel", 1);

        self.lighttracer = .{ .settings = .{
            .min_bounces = min_bounces,
            .max_bounces = max_bounces,
            .full_light_path = full_light_path and !surface_integrator,
        } };
    }

    fn loadPhotonSettings(value: std.json.Value, lighttracer: bool) PhotonSettings {
        return .{
            .num_photons = json.readUIntMember(value, "num_photons", 0),
            .max_bounces = json.readUIntMember(value, "max_bounces", 4),
            .iteration_threshold = json.readFloatMember(value, "iteration_threshold", 1.0),
            .search_radius = json.readFloatMember(value, "search_radius", 0.002),
            .merge_radius = json.readFloatMember(value, "merge_radius", 0.001),
            .full_light_path = json.readBoolMember(value, "full_light_path", false) and !lighttracer,
        };
    }

    fn loadLightSampling(value: std.json.Value, sampling: *LightSampling) void {
        const light_sampling_node = value.object.get("light_sampling") orelse return;

        var iter = light_sampling_node.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "strategy", entry.key_ptr.*)) {
                const strategy = entry.value_ptr.string;

                if (std.mem.eql(u8, "Single", strategy)) {
                    sampling.* = .Single;
                } else if (std.mem.eql(u8, "Adaptive", strategy)) {
                    sampling.* = .Adaptive;
                }
            } else if (std.mem.eql(u8, "splitting_threshold", entry.key_ptr.*)) {
                const st = json.readFloat(f32, entry.value_ptr.*);
                const st2 = st * st;
                LightTree.Splitting_threshold = st2 * st2;
            }
        }
    }

    fn readCausticsResolve(value: std.json.Value, default: CausticsResolve) CausticsResolve {
        const member = value.object.get("caustics") orelse return default;

        switch (member) {
            .bool => |b| return if (b) .Full else .Off,
            .string => |str| {
                if (std.mem.eql(u8, "Off", str)) {
                    return .Off;
                } else if (std.mem.eql(u8, "Rough", str)) {
                    return .Rough;
                } else if (std.mem.eql(u8, "Full", str)) {
                    return .Full;
                }
            },
            else => return default,
        }

        return default;
    }
};

pub const Take = struct {
    resolved_filename: []u8 = &.{},
    scene_filename: []u8 = &.{},

    view: View = .{},

    exporters: Exporters = .{},

    pub fn deinit(self: *Take, alloc: Allocator) void {
        self.clear(alloc);
        self.exporters.deinit(alloc);
        self.view.deinit(alloc);
    }

    pub fn clear(self: *Take, alloc: Allocator) void {
        self.clearExporters(alloc);
        self.view.clear(alloc);
        alloc.free(self.resolved_filename);
        alloc.free(self.scene_filename);
    }

    pub fn clearExporters(self: *Take, alloc: Allocator) void {
        for (self.exporters.items) |*e| {
            e.deinit(alloc);
        }

        self.exporters.clearRetainingCapacity();
    }

    pub fn loadExporters(self: *Take, alloc: Allocator, value: std.json.Value) !void {
        self.clearExporters(alloc);

        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "Image", entry.key_ptr.*)) {
                const format = json.readStringMember(entry.value_ptr.*, "format", "PNG");

                const alpha = self.view.sensor.buffer.alphaTransparency();

                if (std.mem.eql(u8, "EXR", format)) {
                    const bitdepth = json.readUIntMember(entry.value_ptr.*, "bitdepth", 16);
                    try self.exporters.append(alloc, .{ .ImageSequence = .{
                        .writer = .{ .EXR = .{ .half = 16 == bitdepth } },
                        .alpha = alpha,
                    } });
                } else if (std.mem.eql(u8, "RGBE", format)) {
                    try self.exporters.append(alloc, .{ .ImageSequence = .{
                        .writer = .{ .RGBE = .{} },
                        .alpha = false,
                    } });
                } else {
                    const error_diffusion = json.readBoolMember(entry.value_ptr.*, "error_diffusion", false);

                    try self.exporters.append(alloc, .{ .ImageSequence = .{
                        .writer = .{ .PNG = PngWriter.init(error_diffusion) },
                        .alpha = alpha,
                    } });
                }
            } else if (std.mem.eql(u8, "Movie", entry.key_ptr.*)) {
                var dimensions = try alloc.alloc(Vec2i, self.view.cameras.items.len);
                defer alloc.free(dimensions);

                var framerates = try alloc.alloc(u32, self.view.cameras.items.len);
                defer alloc.free(framerates);

                const camera = &self.view.cameras.items[0];

                const framerate = json.readUIntMember(entry.value_ptr.*, "framerate", 0);
                const error_diffusion = json.readBoolMember(entry.value_ptr.*, "error_diffusion", false);

                for (self.view.cameras.items, 0..) |c, i| {
                    dimensions[i] = c.resolution;
                    framerates[i] = if (0 == framerate)
                        @intFromFloat(@round(1.0 / @as(f64, @floatFromInt(camera.frame_step))))
                    else
                        framerate;
                }

                try self.exporters.append(alloc, .{ .FFMPEG = try FFMPEG.init(
                    alloc,
                    dimensions,
                    framerates,
                    error_diffusion,
                ) });
            }
        }
    }
};
