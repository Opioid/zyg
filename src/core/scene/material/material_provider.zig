const log = @import("../../log.zig");
const mat = @import("material.zig");
const Material = mat.Material;
const metal = @import("metal_presets.zig");
const fresnel = @import("fresnel.zig");
const Shape = @import("../shape/shape.zig").Shape;
const Emittance = @import("../light/emittance.zig").Emittance;
const img = @import("../../image/image.zig");
const tx = @import("../../image/texture/texture_provider.zig");
const Texture = tx.Texture;
const TexUsage = tx.Usage;
const ts = @import("../../image/texture/texture_sampler.zig");
const rsc = @import("../../resource/manager.zig");
const Resources = rsc.Manager;
const Result = @import("../../resource/result.zig").Result;
const prcd = @import("../../image/texture/procedural.zig");
const Procedural = prcd.Procedural;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const Vec2f = math.Vec2f;
const json = base.json;
const spectrum = base.spectrum;
const string = base.string;
const Variants = base.memory.VariantMap;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Provider = struct {
    const Error = error{
        NoRenderNode,
        UnknownMaterial,
    };

    const Tex = enum { All, No, DWIM };

    tex: Tex = .All,

    force_debug_material: bool = false,

    pub fn deinit(self: *Provider, alloc: Allocator) void {
        _ = self;
        _ = alloc;
        //  self.parser.deinit();
    }

    pub fn setSettings(self: *Provider, no_tex: bool, no_tex_dwim: bool, force_debug_material: bool) void {
        if (no_tex) {
            self.tex = .No;
        }

        if (no_tex_dwim) {
            self.tex = .DWIM;
        }

        self.force_debug_material = force_debug_material;
    }

    pub fn loadFile(
        self: *Provider,
        alloc: Allocator,
        name: []const u8,
        options: Variants,
        resources: *Resources,
    ) !Result(Material) {
        _ = options;

        const fs = &resources.fs;

        var stream = try fs.readStream(alloc, name);

        const buffer = try stream.readAll(alloc);
        defer alloc.free(buffer);

        stream.deinit();

        try fs.pushMount(alloc, string.parentDirectory(fs.lastResolvedName()));
        defer fs.popMount(alloc);

        var parsed = try std.json.parseFromSlice(std.json.Value, alloc, buffer, .{});
        defer parsed.deinit();

        const root = parsed.value;

        var material = try self.loadMaterial(alloc, root, resources);

        try material.commit(alloc, resources.scene, resources.threads);
        return .{ .data = material };
    }

    pub fn loadData(
        self: *Provider,
        alloc: Allocator,
        data: *align(8) const anyopaque,
        options: Variants,
        resources: *Resources,
    ) !Material {
        _ = options;

        const value: *const std.json.Value = @ptrCast(data);

        var material = try self.loadMaterial(alloc, value.*, resources);
        try material.commit(alloc, resources.scene, resources.threads);
        return material;
    }

    pub fn updateMaterial(
        self: *Provider,
        alloc: Allocator,
        material: *Material,
        value: std.json.Value,
        resources: *Resources,
    ) !void {
        switch (material.*) {
            .Glass => |*m| self.updateGlass(alloc, m, value, resources),
            .Hair => |*m| updateHair(m, value),
            .Light => |*m| self.updateLight(alloc, m, value, resources),
            .Substitute => |*m| self.updateSubstitute(alloc, m, value, resources),
            .Volumetric => |*m| self.updateVolumetric(alloc, m, value, resources),
            else => {},
        }

        try material.commit(alloc, resources.scene, resources.threads);
    }

    pub fn createFallbackMaterial() Material {
        return Material{ .Debug = mat.Debug.init() };
    }

    fn loadMaterial(self: *Provider, alloc: Allocator, value: std.json.Value, resources: *Resources) !Material {
        const rendering_node = value.object.get("rendering") orelse {
            return Error.NoRenderNode;
        };

        var iter = rendering_node.object.iterator();
        while (iter.next()) |entry| {
            if (self.force_debug_material) {
                if (std.mem.eql(u8, "Light", entry.key_ptr.*)) {
                    return self.loadLight(alloc, entry.value_ptr.*, resources);
                } else {
                    return createFallbackMaterial();
                }
            } else {
                if (std.mem.eql(u8, "Debug", entry.key_ptr.*)) {
                    return Material{ .Debug = mat.Debug.init() };
                } else if (std.mem.eql(u8, "Glass", entry.key_ptr.*)) {
                    return self.loadGlass(alloc, entry.value_ptr.*, resources);
                } else if (std.mem.eql(u8, "Hair", entry.key_ptr.*)) {
                    return loadHair(entry.value_ptr.*);
                } else if (std.mem.eql(u8, "Light", entry.key_ptr.*)) {
                    return self.loadLight(alloc, entry.value_ptr.*, resources);
                } else if (std.mem.eql(u8, "Substitute", entry.key_ptr.*)) {
                    return self.loadSubstitute(alloc, entry.value_ptr.*, resources);
                } else if (std.mem.eql(u8, "Volumetric", entry.key_ptr.*)) {
                    return self.loadVolumetric(alloc, entry.value_ptr.*, resources);
                }
            }
        }

        return Error.UnknownMaterial;
    }

    fn loadGlass(self: *Provider, alloc: Allocator, value: std.json.Value, resources: *Resources) Material {
        var material = mat.Glass{};

        self.updateGlass(alloc, &material, value, resources);

        return Material{ .Glass = material };
    }

    fn updateGlass(self: *Provider, alloc: Allocator, material: *mat.Glass, value: std.json.Value, resources: *Resources) void {
        var attenuation_color: Vec4f = @splat(1.0);

        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "mask", entry.key_ptr.*)) {
                material.super.mask = readTexture(alloc, entry.value_ptr.*, .Opacity, self.tex, resources);
            } else if (std.mem.eql(u8, "normal", entry.key_ptr.*)) {
                material.normal_map = readTexture(alloc, entry.value_ptr.*, .Normal, self.tex, resources);
            } else if (std.mem.eql(u8, "color", entry.key_ptr.*) or std.mem.eql(u8, "attenuation_color", entry.key_ptr.*)) {
                attenuation_color = json.readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "attenuation_distance", entry.key_ptr.*)) {
                material.attenuation_distance = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "roughness", entry.key_ptr.*)) {
                material.roughness = readValue(alloc, entry.value_ptr.*, .Roughness, self.tex, resources);
            } else if (std.mem.eql(u8, "priority", entry.key_ptr.*)) {
                material.super.priority = @intCast(json.readInt(entry.value_ptr.*));
            } else if (std.mem.eql(u8, "ior", entry.key_ptr.*)) {
                material.ior = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "abbe", entry.key_ptr.*)) {
                material.abbe = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "thickness", entry.key_ptr.*)) {
                material.thickness = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
                material.super.sampler_key = readSamplerKey(entry.value_ptr.*);
            }
        }

        material.setVolumetric(attenuation_color, material.attenuation_distance);
    }

    fn loadHair(value: std.json.Value) Material {
        var material = mat.Hair{};

        updateHair(&material, value);

        return Material{ .Hair = material };
    }

    fn updateHair(material: *mat.Hair, value: std.json.Value) void {
        var eumelanin: f32 = -1.0;
        var pheomelanin: f32 = 0.0;

        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "color", entry.key_ptr.*)) {
                material.color = json.readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "roughness", entry.key_ptr.*)) {
                material.roughness = json.readVec2f(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "eumelanin", entry.key_ptr.*)) {
                eumelanin = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "pheomelanin", entry.key_ptr.*)) {
                pheomelanin = json.readFloat(f32, entry.value_ptr.*);
            }
        }

        if (eumelanin > 0.0) {
            material.setMelanin(eumelanin, pheomelanin);
        }
    }

    fn loadLight(self: *Provider, alloc: Allocator, value: std.json.Value, resources: *Resources) Material {
        var material = mat.Light{};

        self.updateLight(alloc, &material, value, resources);

        return Material{ .Light = material };
    }

    fn updateLight(self: *Provider, alloc: Allocator, material: *mat.Light, value: std.json.Value, resources: *Resources) void {
        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "mask", entry.key_ptr.*)) {
                material.super.mask = readTexture(alloc, entry.value_ptr.*, .Opacity, self.tex, resources);
            } else if (std.mem.eql(u8, "emittance", entry.key_ptr.*)) {
                loadEmittance(alloc, entry.value_ptr.*, self.tex, resources, &material.emittance);
            } else if (std.mem.eql(u8, "two_sided", entry.key_ptr.*)) {
                material.super.setTwoSided(json.readBool(entry.value_ptr.*));
            } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
                material.super.sampler_key = readSamplerKey(entry.value_ptr.*);
            }
        }
    }

    fn loadSubstitute(self: *Provider, alloc: Allocator, value: std.json.Value, resources: *Resources) Material {
        var material = mat.Substitute{};

        self.updateSubstitute(alloc, &material, value, resources);

        return Material{ .Substitute = material };
    }

    fn updateSubstitute(self: *Provider, alloc: Allocator, material: *mat.Substitute, value: std.json.Value, resources: *Resources) void {
        var attenuation_color: Vec4f = @splat(0.0);
        var subsurface_color: Vec4f = @splat(0.0);

        var attenuation_distance: f32 = 0.0;
        var volumetric_anisotropy: f32 = 0.0;

        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "mask", entry.key_ptr.*)) {
                material.super.mask = readTexture(alloc, entry.value_ptr.*, .Opacity, self.tex, resources);
            } else if (std.mem.eql(u8, "color", entry.key_ptr.*)) {
                material.color = readValue(alloc, entry.value_ptr.*, .Color, self.tex, resources);
            } else if (std.mem.eql(u8, "normal", entry.key_ptr.*)) {
                material.normal_map = readTexture(alloc, entry.value_ptr.*, .Normal, self.tex, resources);
            } else if (std.mem.eql(u8, "emittance", entry.key_ptr.*)) {
                loadEmittance(alloc, entry.value_ptr.*, self.tex, resources, &material.emittance);
            } else if (std.mem.eql(u8, "roughness", entry.key_ptr.*)) {
                material.roughness = readValue(alloc, entry.value_ptr.*, .Roughness, self.tex, resources);
            } else if (std.mem.eql(u8, "surface", entry.key_ptr.*)) {
                log.warning("Surface maps are no longer supported. Please use separate roughness and metallic maps instead.", .{});
            } else if (std.mem.eql(u8, "metal_preset", entry.key_ptr.*)) {
                const eta_k = metal.iorAndAbsorption(entry.value_ptr.string);
                material.color = Texture.initUniform3(fresnel.conductor(eta_k[0], eta_k[1], 1.0));
                material.metallic = Texture.initUniform1(1.0);
            } else if (std.mem.eql(u8, "attenuation_color", entry.key_ptr.*)) {
                attenuation_color = json.readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "subsurface_color", entry.key_ptr.*)) {
                subsurface_color = json.readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "anisotropy_rotation", entry.key_ptr.*)) {
                material.rotation = readValue(alloc, entry.value_ptr.*, .Roughness, self.tex, resources);
            } else if (std.mem.eql(u8, "anisotropy", entry.key_ptr.*)) {
                material.anisotropy = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "metallic", entry.key_ptr.*)) {
                material.metallic = readValue(alloc, entry.value_ptr.*, .Roughness, self.tex, resources);
            } else if (std.mem.eql(u8, "ior", entry.key_ptr.*)) {
                material.ior = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "priority", entry.key_ptr.*)) {
                material.super.priority = @intCast(json.readInt(entry.value_ptr.*));
            } else if (std.mem.eql(u8, "two_sided", entry.key_ptr.*)) {
                material.super.setTwoSided(json.readBool(entry.value_ptr.*));
            } else if (std.mem.eql(u8, "thickness", entry.key_ptr.*)) {
                material.thickness = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "attenuation_distance", entry.key_ptr.*)) {
                attenuation_distance = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "volumetric_anisotropy", entry.key_ptr.*)) {
                volumetric_anisotropy = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
                material.super.sampler_key = readSamplerKey(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "coating", entry.key_ptr.*)) {
                var coating_color: Vec4f = @splat(1.0);
                var coating_attenuation_distance: f32 = 0.1;

                var citer = entry.value_ptr.object.iterator();
                while (citer.next()) |c| {
                    if (std.mem.eql(u8, "color", c.key_ptr.*)) {
                        coating_color = json.readColor(c.value_ptr.*);
                    } else if (std.mem.eql(u8, "attenuation_distance", c.key_ptr.*)) {
                        coating_attenuation_distance = json.readFloat(f32, c.value_ptr.*);
                    } else if (std.mem.eql(u8, "ior", c.key_ptr.*)) {
                        material.coating_ior = json.readFloat(f32, c.value_ptr.*);
                    } else if (std.mem.eql(u8, "normal", c.key_ptr.*)) {
                        material.coating_normal_map = readTexture(alloc, c.value_ptr.*, .Normal, self.tex, resources);
                    } else if (std.mem.eql(u8, "roughness", c.key_ptr.*)) {
                        material.coating_roughness = readValue(alloc, c.value_ptr.*, .Roughness, self.tex, resources);
                    } else if (std.mem.eql(u8, "scale", c.key_ptr.*)) {
                        material.coating_scale = readValue(alloc, c.value_ptr.*, .Roughness, self.tex, resources);
                    } else if (std.mem.eql(u8, "thickness", c.key_ptr.*)) {
                        material.coating_thickness = json.readFloat(f32, c.value_ptr.*);
                    }
                }

                material.setCoatingAttenuation(coating_color, coating_attenuation_distance);
            } else if (std.mem.eql(u8, "flakes", entry.key_ptr.*)) {
                var citer = entry.value_ptr.object.iterator();
                while (citer.next()) |c| {
                    if (std.mem.eql(u8, "color", c.key_ptr.*)) {
                        material.flakes_color = json.readColor(c.value_ptr.*);
                    } else if (std.mem.eql(u8, "coverage", c.key_ptr.*)) {
                        material.flakes_coverage = readValue(alloc, c.value_ptr.*, .Roughness, self.tex, resources);
                    } else if (std.mem.eql(u8, "roughness", c.key_ptr.*)) {
                        material.setFlakesRoughness(json.readFloat(f32, c.value_ptr.*));
                    } else if (std.mem.eql(u8, "size", c.key_ptr.*)) {
                        material.setFlakesSize(json.readFloat(f32, c.value_ptr.*));
                    }
                }
            }
        }

        material.setVolumetric(
            attenuation_color,
            subsurface_color,
            attenuation_distance,
            volumetric_anisotropy,
        );
    }

    fn loadVolumetric(self: *Provider, alloc: Allocator, value: std.json.Value, resources: *Resources) !Material {
        var material = mat.Volumetric.init();

        self.updateVolumetric(alloc, &material, value, resources);

        return Material{ .Volumetric = material };
    }

    fn updateVolumetric(
        self: *Provider,
        alloc: Allocator,
        material: *mat.Volumetric,
        value: std.json.Value,
        resources: *Resources,
    ) void {
        var color: Vec4f = @splat(0.5);

        var attenuation_color: Vec4f = @splat(1.0);
        var subsurface_color: Vec4f = @splat(0.0);

        var use_attenuation_color = false;
        var use_subsurface_color = false;

        var attenuation_distance: f32 = 0.0;
        var volumetric_anisotropy: f32 = 0.0;

        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "density", entry.key_ptr.*)) {
                material.density_map = readTexture(alloc, entry.value_ptr.*, .Roughness, self.tex, resources);
            } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
                material.super.sampler_key = readSamplerKey(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "color", entry.key_ptr.*)) {
                color = json.readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "emittance", entry.key_ptr.*)) {
                loadEmittance(alloc, entry.value_ptr.*, self.tex, resources, &material.emittance);
            } else if (std.mem.eql(u8, "attenuation_color", entry.key_ptr.*)) {
                attenuation_color = json.readColor(entry.value_ptr.*);
                use_attenuation_color = true;
            } else if (std.mem.eql(u8, "subsurface_color", entry.key_ptr.*)) {
                subsurface_color = json.readColor(entry.value_ptr.*);
                use_subsurface_color = true;
            } else if (std.mem.eql(u8, "attenuation_distance", entry.key_ptr.*)) {
                attenuation_distance = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "anisotropy", entry.key_ptr.*)) {
                volumetric_anisotropy = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "similarity_relation_range", entry.key_ptr.*)) {
                const sr_range = json.readVec2i(entry.value_ptr.*);
                material.setSimilarityRelationRange(@bitCast(sr_range[0]), @bitCast(sr_range[1]));
            }
        }

        if (!use_attenuation_color) {
            attenuation_color = color;
        }

        if (!use_subsurface_color) {
            subsurface_color = color;
        }

        material.setVolumetric(
            attenuation_color,
            subsurface_color,
            attenuation_distance,
            volumetric_anisotropy,
        );
    }
};

fn loadEmittance(alloc: Allocator, jvalue: std.json.Value, tex: Provider.Tex, resources: *Resources, emittance: *Emittance) void {
    if (jvalue.object.get("profile")) |p| {
        emittance.profile = readTexture(alloc, p, .Emission, tex, resources);
    }

    if (jvalue.object.get("emission_map")) |em| {
        emittance.emission_map = readValue(alloc, em, .Emission, tex, resources);
    } else if (jvalue.object.get("temperature_map")) |tm| {
        emittance.emission_map = readValue(alloc, tm, .Roughness, tex, resources);
    }

    const profile_angle = math.radiansToDegrees(emittance.angleFromProfile(resources.scene));

    var color: Vec4f = @splat(1.0);
    if (jvalue.object.get("spectrum")) |s| {
        color = json.readColor(s);
    }

    const cos_a = @cos(math.degreesToRadians(json.readFloatMember(jvalue, "angle", profile_angle)));

    const value = json.readFloatMember(jvalue, "value", 1.0);

    const quantity = json.readStringMember(jvalue, "quantity", "");

    if (std.mem.eql(u8, "Flux", quantity)) {
        emittance.setLuminousFlux(color, value, cos_a);
    } else if (std.mem.eql(u8, "Luminous_intensity", quantity)) {
        emittance.setLuminousIntensity(color, value, cos_a);
    } else if (std.mem.eql(u8, "Luminance", quantity)) {
        emittance.setLuminance(color, value, cos_a);
    } else if (std.mem.eql(u8, "Radiant_intensity", quantity)) {
        emittance.setRadiantIntensity(@as(Vec4f, @splat(value)) * color, cos_a);
    } else // if (std.mem.eql(u8, "Radiance", quantity))
    {
        emittance.setRadiance(@as(Vec4f, @splat(value)) * color, cos_a);
    }

    emittance.num_samples = @min(json.readUIntMember(jvalue, "num_samples", 1), Shape.MaxSamples);
}

const TextureDescriptor = struct {
    filename: ?[]u8 = null,
    procedural: u32 = rsc.Null,
    procedural_data: u32 = rsc.Null,
    id: u32 = rsc.Null,

    swizzle: ?img.Swizzle = null,

    sampler: Texture.TexCoordMode = .UV0,
    scale: Vec2f = .{ 1.0, 1.0 },

    invert: bool = false,

    pub fn init(
        alloc: Allocator,
        value: std.json.Value,
        usage: TexUsage,
        tex: Provider.Tex,
        resources: *Resources,
    ) !TextureDescriptor {
        var desc = TextureDescriptor{};

        switch (value) {
            .object => |o| {
                var iter = o.iterator();
                while (iter.next()) |entry| {
                    if (std.mem.eql(u8, "Checker", entry.key_ptr.*)) {
                        desc.procedural = @intFromEnum(Procedural.Type.Checker);
                        desc.procedural_data = try resources.scene.procedural.append(alloc, prcd.Checker.init(entry.value_ptr.*));
                    } else if (std.mem.eql(u8, "DetailNormal", entry.key_ptr.*)) {
                        var detail: prcd.DetailNormal = .{
                            .base = Texture.initUniform1(0.0),
                            .detail = Texture.initUniform1(0.0),
                        };

                        var citer = entry.value_ptr.object.iterator();
                        while (citer.next()) |cn| {
                            if (std.mem.eql(u8, "base", cn.key_ptr.*)) {
                                detail.base = readValue(alloc, cn.value_ptr.*, usage, tex, resources);
                            } else if (std.mem.eql(u8, "detail", cn.key_ptr.*)) {
                                detail.detail = readValue(alloc, cn.value_ptr.*, usage, tex, resources);
                            }
                        }

                        desc.procedural = @intFromEnum(Procedural.Type.DetailNormal);
                        desc.procedural_data = try resources.scene.procedural.append(alloc, detail);
                    } else if (std.mem.eql(u8, "Max", entry.key_ptr.*)) {
                        var max: prcd.Max = .{
                            .a = Texture.initUniform1(0.0),
                            .b = Texture.initUniform1(0.0),
                        };

                        var citer = entry.value_ptr.object.iterator();
                        while (citer.next()) |cn| {
                            if (std.mem.eql(u8, "a", cn.key_ptr.*)) {
                                max.a = readValue(alloc, cn.value_ptr.*, usage, tex, resources);
                            } else if (std.mem.eql(u8, "b", cn.key_ptr.*)) {
                                max.b = readValue(alloc, cn.value_ptr.*, usage, tex, resources);
                            }
                        }

                        desc.procedural = @intFromEnum(Procedural.Type.Max);
                        desc.procedural_data = try resources.scene.procedural.append(alloc, max);
                    } else if (std.mem.eql(u8, "Mix", entry.key_ptr.*)) {
                        var mix: prcd.Mix = .{
                            .a = Texture.initUniform1(0.0),
                            .b = Texture.initUniform1(0.0),
                            .t = Texture.initUniform1(0.0),
                        };

                        var citer = entry.value_ptr.object.iterator();
                        while (citer.next()) |cn| {
                            if (std.mem.eql(u8, "a", cn.key_ptr.*)) {
                                mix.a = readValue(alloc, cn.value_ptr.*, usage, tex, resources);
                            } else if (std.mem.eql(u8, "b", cn.key_ptr.*)) {
                                mix.b = readValue(alloc, cn.value_ptr.*, usage, tex, resources);
                            } else if (std.mem.eql(u8, "weight", cn.key_ptr.*)) {
                                mix.t = readValue(alloc, cn.value_ptr.*, .Opacity, tex, resources);
                            }
                        }
                        desc.procedural = @intFromEnum(Procedural.Type.Mix);
                        desc.procedural_data = try resources.scene.procedural.append(alloc, mix);
                    } else if (std.mem.eql(u8, "Mul", entry.key_ptr.*)) {
                        var mul: prcd.Mul = .{
                            .a = Texture.initUniform1(0.0),
                            .b = Texture.initUniform1(0.0),
                        };

                        var citer = entry.value_ptr.object.iterator();
                        while (citer.next()) |cn| {
                            if (std.mem.eql(u8, "a", cn.key_ptr.*)) {
                                mul.a = readValue(alloc, cn.value_ptr.*, usage, tex, resources);
                            } else if (std.mem.eql(u8, "b", cn.key_ptr.*)) {
                                mul.b = readValue(alloc, cn.value_ptr.*, usage, tex, resources);
                            }
                        }

                        desc.procedural = @intFromEnum(Procedural.Type.Mul);
                        desc.procedural_data = try resources.scene.procedural.append(alloc, mul);
                    } else if (std.mem.eql(u8, "Noise", entry.key_ptr.*)) {
                        var noise: prcd.Noise = undefined;

                        noise.class = .Gradient;

                        const class_str = json.readStringMember(entry.value_ptr.*, "class", "");
                        if (std.mem.eql(u8, "Cellular", class_str)) {
                            noise.class = .Cellular;
                        }

                        noise.flags.absolute = json.readBoolMember(entry.value_ptr.*, "absolute", false);
                        noise.flags.invert = json.readBoolMember(entry.value_ptr.*, "invert", false);
                        noise.levels = json.readUIntMember(entry.value_ptr.*, "levels", 1);
                        noise.attenuation = json.readFloatMember(entry.value_ptr.*, "attenuation", 0.0);
                        noise.ratio = json.readFloatMember(entry.value_ptr.*, "ratio", 0.5);
                        noise.transition = json.readFloatMember(entry.value_ptr.*, "transition", 0.5);
                        noise.scale = json.readVec4f3Member(entry.value_ptr.*, "scale", @splat(1.0));

                        desc.procedural = @intFromEnum(Procedural.Type.Noise);
                        desc.procedural_data = try resources.scene.procedural.append(alloc, noise);
                    } else if (std.mem.eql(u8, "file", entry.key_ptr.*)) {
                        desc.filename = try alloc.dupe(u8, entry.value_ptr.string);
                    } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
                        desc.sampler = readTextureSampler(entry.value_ptr.*);
                    } else if (std.mem.eql(u8, "id", entry.key_ptr.*)) {
                        desc.id = json.readUInt(entry.value_ptr.*);
                    } else if (std.mem.eql(u8, "swizzle", entry.key_ptr.*)) {
                        const swizzle = entry.value_ptr.string;

                        if (std.mem.eql(u8, "X", swizzle)) {
                            desc.swizzle = .X;
                        } else if (std.mem.eql(u8, "Y", swizzle)) {
                            desc.swizzle = .Y;
                        } else if (std.mem.eql(u8, "Z", swizzle)) {
                            desc.swizzle = .Z;
                        } else if (std.mem.eql(u8, "W", swizzle)) {
                            desc.swizzle = .W;
                        } else if (std.mem.eql(u8, "YX", swizzle)) {
                            desc.swizzle = .YX;
                        } else if (std.mem.eql(u8, "YZ", swizzle)) {
                            desc.swizzle = .YZ;
                        }
                    } else if (std.mem.eql(u8, "scale", entry.key_ptr.*)) {
                        desc.scale = switch (entry.value_ptr.*) {
                            .array => json.readVec2f(entry.value_ptr.*),
                            else => @splat(json.readFloat(f32, entry.value_ptr.*)),
                        };
                    } else if (std.mem.eql(u8, "invert", entry.key_ptr.*)) {
                        desc.invert = json.readBool(entry.value_ptr.*);
                    }
                }
            },
            else => {},
        }

        return desc;
    }

    pub fn deinit(self: *TextureDescriptor, alloc: Allocator) void {
        if (self.filename) |filename| {
            alloc.free(filename);
        }
    }
};

fn readSamplerKey(value: std.json.Value) ts.Key {
    var key = ts.Key{};

    switch (value) {
        .object => |o| {
            var iter = o.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "filter", entry.key_ptr.*)) {
                    const filter = json.readString(entry.value_ptr.*);

                    if (std.mem.eql(u8, "Nearest", filter)) {
                        key.filter = .Nearest;
                    } else if (std.mem.eql(u8, "Linear", filter)) {
                        key.filter = .LinearStochastic;
                    }
                } else if (std.mem.eql(u8, "address", entry.key_ptr.*)) {
                    switch (entry.value_ptr.*) {
                        .array => |a| {
                            key.address.u = readAddress(a.items[0]);
                            key.address.v = readAddress(a.items[1]);
                        },
                        else => {
                            const adr = readAddress(entry.value_ptr.*);
                            key.address.u = adr;
                            key.address.v = adr;
                        },
                    }
                }
            }
        },
        else => {},
    }

    return key;
}

fn readAddress(value: std.json.Value) ts.AddressMode {
    const address = json.readString(value);

    if (std.mem.eql(u8, "Clamp", address)) {
        return .Clamp;
    }

    return .Repeat;
}

fn readTextureSampler(value: std.json.Value) Texture.TexCoordMode {
    var sampler: Texture.TexCoordMode = .UV0;

    switch (value) {
        .object => |o| {
            var iter = o.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "texcoord", entry.key_ptr.*)) {
                    const set = json.readString(entry.value_ptr.*);

                    if (std.mem.eql(u8, "UV0", set)) {
                        sampler = .UV0;
                    } else if (std.mem.eql(u8, "Triplanar", set)) {
                        sampler = .Triplanar;
                    } else if (std.mem.eql(u8, "ObjectPos", set)) {
                        sampler = .ObjectPos;
                    }
                }
            }
        },
        else => {},
    }

    return sampler;
}

fn readTexture(
    alloc: Allocator,
    value: std.json.Value,
    usage: TexUsage,
    tex: Provider.Tex,
    resources: *Resources,
) Texture {
    var desc = TextureDescriptor.init(alloc, value, usage, tex, resources) catch return .{};
    defer desc.deinit(alloc);

    return createTexture(alloc, desc, usage, tex, resources);
}

fn createTexture(
    alloc: Allocator,
    desc: TextureDescriptor,
    usage: TexUsage,
    tex: Provider.Tex,
    resources: *Resources,
) Texture {
    if (tex == .No or (tex == .DWIM and usage != .Emission and usage != .Opacity)) {
        return .{};
    }

    if (rsc.Null != desc.procedural) {
        return Texture.initProcedural(desc.procedural, desc.procedural_data, desc.sampler);
    } else if (desc.filename) |filename| {
        var options: Variants = .{};
        defer options.deinit(alloc);
        options.set(alloc, "usage", usage) catch {};

        if (desc.invert) {
            options.set(alloc, "invert", true) catch {};
        }

        if (desc.swizzle) |swizzle| {
            options.set(alloc, "swizzle", swizzle) catch {};
        }

        return tx.Provider.loadFile(alloc, filename, options, desc.sampler, desc.scale, resources) catch |e| {
            log.err("Could not load texture \"{s}\": {}", .{ filename, e });
            return .{};
        };
    } else if (rsc.Null != desc.id) {
        return tx.Provider.createTexture(desc.id, usage, desc.sampler, desc.scale, resources) catch |e| {
            log.err("Could not create texture \"{}\": {}", .{ desc.id, e });
            return .{};
        };
    }

    return .{};
}

fn readValue(alloc: Allocator, value: std.json.Value, usage: TexUsage, tex: Provider.Tex, resources: *Resources) Texture {
    return switch (usage) {
        .Emission, .Color, .ColorAndOpacity => readTypedValue(Vec4f, alloc, value, @splat(0.0), usage, tex, resources),
        .Normal => readTypedValue(Vec2f, alloc, value, @splat(0.0), usage, tex, resources),
        else => readTypedValue(f32, alloc, value, 0.0, usage, tex, resources),
    };
}

fn readTypedValue(
    comptime Value: type,
    alloc: Allocator,
    value: std.json.Value,
    comptime default: Value,
    usage: TexUsage,
    tex: Provider.Tex,
    resources: *Resources,
) Texture {
    var result_texture: Texture = .{};
    var result_value = default;

    if (Vec4f == Value) {
        switch (value) {
            .object => {
                var desc = TextureDescriptor.init(alloc, value, usage, tex, resources) catch return Texture.initUniform3(default);
                defer desc.deinit(alloc);

                result_texture = createTexture(alloc, desc, usage, tex, resources);

                if (value.object.get("value")) |n| {
                    result_value = json.readColor(n);
                }
            },
            else => result_value = json.readColor(value),
        }
    } else if (Vec2f == Value) {
        switch (value) {
            .object => {
                var desc = TextureDescriptor.init(alloc, value, usage, tex, resources) catch return Texture.initUniform2(default);
                defer desc.deinit(alloc);

                result_texture = createTexture(alloc, desc, usage, tex, resources);
                result_value = json.readVec2fMember(value, "value", default);
            },
            else => result_value = json.readVec2f(value),
        }
    } else {
        switch (value) {
            .object => {
                var desc = TextureDescriptor.init(alloc, value, usage, tex, resources) catch return Texture.initUniform1(default);
                defer desc.deinit(alloc);

                result_texture = createTexture(alloc, desc, usage, tex, resources);
                result_value = json.readFloatMember(value, "value", default);
            },
            else => result_value = json.readFloat(f32, value),
        }
    }

    if (!result_texture.isUniform()) {
        return result_texture;
    }

    if (Vec4f == Value) {
        return Texture.initUniform3(result_value);
    } else if (Vec2f == Value) {
        return Texture.initUniform2(result_value);
    } else {
        return Texture.initUniform1(result_value);
    }
}
