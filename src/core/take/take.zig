const aov = @import("../rendering/sensor/aov/aov_value.zig");
const surface = @import("../rendering/integrator/surface/integrator.zig");
const lt = @import("../rendering/integrator/particle/lighttracer.zig");
const LightSampling = @import("../rendering/integrator/helper.zig").LightSampling;
const LightTree = @import("../scene/light/light_tree.zig");
const SamplerFactory = @import("../sampler/sampler.zig").Factory;
const cam = @import("../camera/perspective.zig");
const Sink = @import("../exporting/sink.zig").Sink;
const MaterialBase = @import("../scene/material/material_base.zig").Base;
const PngWriter = @import("../image/encoding/png/png_writer.zig").Writer;
const FFMPEG = @import("../exporting/ffmpeg.zig").FFMPEG;

const base = @import("base");
const json = base.json;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Exporters = std.ArrayListUnmanaged(Sink);

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

    surfaces: surface.Factory = .{ .AOV = .{
        .settings = .{
            .value = .AO,
            .num_samples = 1,
            .max_bounces = 1,
            .radius = 1.0,
            .photons_not_only_through_specular = false,
        },
    } },

    lighttracers: lt.Factory = .{ .settings = .{
        .min_bounces = 0,
        .max_bounces = 0,
        .full_light_path = false,
    } },

    aovs: aov.Factory = .{},

    camera: cam.Perspective = .{},

    num_samples_per_pixel: u32 = 0,
    num_particles_per_pixel: u32 = 0,

    photon_settings: PhotonSettings = .{},

    pub const AovValue = aov.Value;

    pub fn deinit(self: *View, alloc: Allocator) void {
        self.camera.deinit(alloc);
    }

    pub fn configure(self: *View) void {
        const spp = if (self.num_samples_per_pixel > 0) self.num_samples_per_pixel else self.num_particles_per_pixel;
        self.camera.sample_spacing = 1.0 / @sqrt(@floatFromInt(f32, spp));
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
        const Default_min_bounces = 4;
        const Default_max_bounces = 8;

        var light_sampling = LightSampling.Adaptive;

        const Default_caustics = true;

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

                self.surfaces = surface.Factory{ .AOV = .{
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
                const enable_caustics = json.readBoolMember(entry.value_ptr.*, "caustics", Default_caustics);

                self.surfaces = surface.Factory{ .PT = .{
                    .settings = .{
                        .min_bounces = min_bounces,
                        .max_bounces = max_bounces,
                        .avoid_caustics = !enable_caustics,
                    },
                } };
            } else if (std.mem.eql(u8, "PTDL", entry.key_ptr.*)) {
                const min_bounces = json.readUIntMember(entry.value_ptr.*, "min_bounces", Default_min_bounces);
                const max_bounces = json.readUIntMember(entry.value_ptr.*, "max_bounces", Default_max_bounces);
                const enable_caustics = json.readBoolMember(entry.value_ptr.*, "caustics", Default_caustics);

                loadLightSampling(entry.value_ptr.*, &light_sampling);

                self.surfaces = surface.Factory{ .PTDL = .{
                    .settings = .{
                        .min_bounces = min_bounces,
                        .max_bounces = max_bounces,
                        .light_sampling = light_sampling,
                        .avoid_caustics = !enable_caustics,
                    },
                } };
            } else if (std.mem.eql(u8, "PTMIS", entry.key_ptr.*)) {
                const min_bounces = json.readUIntMember(entry.value_ptr.*, "min_bounces", Default_min_bounces);
                const max_bounces = json.readUIntMember(entry.value_ptr.*, "max_bounces", Default_max_bounces);
                const enable_caustics = json.readBoolMember(entry.value_ptr.*, "caustics", Default_caustics) and !lighttracer;

                loadLightSampling(entry.value_ptr.*, &light_sampling);

                self.surfaces = surface.Factory{ .PTMIS = .{
                    .settings = .{
                        .min_bounces = min_bounces,
                        .max_bounces = max_bounces,
                        .light_sampling = light_sampling,
                        .avoid_caustics = !enable_caustics,
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
                MaterialBase.setSimilarityRelationRange(@intCast(u32, sr_range[0]), @intCast(u32, sr_range[1]));
            }
        }
    }

    fn loadParticleIntegrator(self: *View, value: std.json.Value, surface_integrator: bool) void {
        const max_bounces = json.readUIntMember(value, "max_bounces", 8);
        const full_light_path = json.readBoolMember(value, "full_light_path", true);
        self.num_particles_per_pixel = json.readUIntMember(value, "particles_per_pixel", 1);

        self.lighttracers = lt.Factory{ .settings = .{
            .min_bounces = 1,
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

                const alpha = self.view.camera.sensor.alphaTransparency();

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
                var framerate = json.readUIntMember(entry.value_ptr.*, "framerate", 0);
                if (0 == framerate) {
                    framerate = @intFromFloat(u32, @round(1.0 / @floatFromInt(f64, self.view.camera.frame_step)));
                }

                const error_diffusion = json.readBoolMember(entry.value_ptr.*, "error_diffusion", false);

                try self.exporters.append(alloc, .{ .FFMPEG = try FFMPEG.init(
                    alloc,
                    self.view.camera.sensorDimensions(),
                    framerate,
                    error_diffusion,
                ) });
            }
        }
    }
};
