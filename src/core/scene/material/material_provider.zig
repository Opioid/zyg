const log = @import("../../log.zig");
const mat = @import("material.zig");
const Material = mat.Material;
const MappedValue = mat.Base.MappedValue;
const metal = @import("metal_presets.zig");
const fresnel = @import("fresnel.zig");
const Emittance = @import("../light/emittance.zig").Emittance;
const img = @import("../../image/image.zig");
const tx = @import("../../image/texture/texture_provider.zig");
const Texture = tx.Texture;
const TexUsage = tx.Usage;
const ts = @import("../../image/texture/texture_sampler.zig");
const rsc = @import("../../resource/manager.zig");
const Resources = rsc.Manager;
const Result = @import("../../resource/result.zig").Result;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const Vec2f = math.Vec2f;
const json = base.json;
const spectrum = base.spectrum;
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
        self: Provider,
        alloc: Allocator,
        name: []const u8,
        options: Variants,
        resources: *Resources,
    ) !Result(Material) {
        _ = options;

        var stream = try resources.fs.readStream(alloc, name);

        const buffer = try stream.readAll(alloc);
        defer alloc.free(buffer);

        stream.deinit();

        var parser = std.json.Parser.init(alloc, false);
        defer parser.deinit();

        var document = try parser.parse(buffer);
        defer document.deinit();

        const root = document.root;

        var material = try self.loadMaterial(alloc, root, resources);

        try material.commit(alloc, resources.scene, resources.threads);
        return .{ .data = material };
    }

    pub fn loadData(
        self: Provider,
        alloc: Allocator,
        data: usize,
        options: Variants,
        resources: *Resources,
    ) !Material {
        _ = options;

        const value = @intToPtr(*std.json.Value, data);

        var material = try self.loadMaterial(alloc, value.*, resources);
        try material.commit(alloc, resources.scene, resources.threads);
        return material;
    }

    pub fn updateMaterial(
        self: Provider,
        alloc: Allocator,
        material: *Material,
        value: std.json.Value,
        resources: *Resources,
    ) !void {
        switch (material.*) {
            .Glass => |*g| self.updateGlass(alloc, g, value, resources),
            .Light => |*g| self.updateLight(alloc, g, value, resources),
            .Substitute => |*g| self.updateSubstitute(alloc, g, value, resources),
            .Volumetric => |*g| self.updateVolumetric(alloc, g, value, resources),
            else => {},
        }

        try material.commit(alloc, resources.scene, resources.threads);
    }

    pub fn createFallbackMaterial() Material {
        return Material{ .Debug = mat.Debug.init() };
    }

    fn loadMaterial(self: Provider, alloc: Allocator, value: std.json.Value, resources: *Resources) !Material {
        const rendering_node = value.Object.get("rendering") orelse {
            return Error.NoRenderNode;
        };

        var iter = rendering_node.Object.iterator();
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

    fn loadGlass(self: Provider, alloc: Allocator, value: std.json.Value, resources: *Resources) Material {
        var material = mat.Glass{ .super = .{
            .ior = 1.46,
            .attenuation_distance = 1.0,
        } };

        self.updateGlass(alloc, &material, value, resources);

        return Material{ .Glass = material };
    }

    fn updateGlass(self: Provider, alloc: Allocator, material: *mat.Glass, value: std.json.Value, resources: *Resources) void {
        var attenuation_color = @splat(4, @as(f32, 1.0));

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "mask", entry.key_ptr.*)) {
                material.super.mask = readTexture(alloc, entry.value_ptr.*, .Opacity, self.tex, resources);
            } else if (std.mem.eql(u8, "normal", entry.key_ptr.*)) {
                material.normal_map = readTexture(alloc, entry.value_ptr.*, .Normal, self.tex, resources);
            } else if (std.mem.eql(u8, "color", entry.key_ptr.*) or std.mem.eql(u8, "attenuation_color", entry.key_ptr.*)) {
                attenuation_color = readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "attenuation_distance", entry.key_ptr.*)) {
                material.super.attenuation_distance = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "roughness", entry.key_ptr.*)) {
                material.setRoughness(readValue(f32, alloc, entry.value_ptr.*, material.roughness, .Roughness, self.tex, resources));
            } else if (std.mem.eql(u8, "ior", entry.key_ptr.*)) {
                material.super.ior = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "abbe", entry.key_ptr.*)) {
                material.abbe = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "thickness", entry.key_ptr.*)) {
                material.thickness = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
                material.super.sampler_key = readSamplerKey(entry.value_ptr.*);
            }
        }

        material.super.setVolumetric(attenuation_color, @splat(4, @as(f32, 0.0)), material.super.attenuation_distance, 0.0);
    }

    fn loadLight(self: Provider, alloc: Allocator, value: std.json.Value, resources: *Resources) Material {
        var material = mat.Light{};

        self.updateLight(alloc, &material, value, resources);

        return Material{ .Light = material };
    }

    fn updateLight(self: Provider, alloc: Allocator, material: *mat.Light, value: std.json.Value, resources: *Resources) void {
        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "mask", entry.key_ptr.*)) {
                material.super.mask = readTexture(alloc, entry.value_ptr.*, .Opacity, self.tex, resources);
            } else if (std.mem.eql(u8, "emission", entry.key_ptr.*)) {
                material.emission_map = readTexture(alloc, entry.value_ptr.*, .Emission, self.tex, resources);
            } else if (std.mem.eql(u8, "emittance", entry.key_ptr.*)) {
                loadEmittance(alloc, entry.value_ptr.*, self.tex, resources, &material.super.emittance);
            } else if (std.mem.eql(u8, "two_sided", entry.key_ptr.*)) {
                material.super.setTwoSided(json.readBool(entry.value_ptr.*));
            } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
                material.super.sampler_key = readSamplerKey(entry.value_ptr.*);
            }
        }
    }

    fn loadSubstitute(self: Provider, alloc: Allocator, value: std.json.Value, resources: *Resources) Material {
        var material = mat.Substitute{ .super = .{ .ior = 1.46 } };

        self.updateSubstitute(alloc, &material, value, resources);

        return Material{ .Substitute = material };
    }

    fn updateSubstitute(self: Provider, alloc: Allocator, material: *mat.Substitute, value: std.json.Value, resources: *Resources) void {
        var attenuation_color = @splat(4, @as(f32, 0.0));
        var subsurface_color = @splat(4, @as(f32, 0.0));

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "mask", entry.key_ptr.*)) {
                material.super.mask = readTexture(alloc, entry.value_ptr.*, .Opacity, self.tex, resources);
            } else if (std.mem.eql(u8, "color", entry.key_ptr.*)) {
                material.setColor(readValue(Vec4f, alloc, entry.value_ptr.*, material.color, .Color, self.tex, resources));
            } else if (std.mem.eql(u8, "normal", entry.key_ptr.*)) {
                material.normal_map = readTexture(alloc, entry.value_ptr.*, .Normal, self.tex, resources);
            } else if (std.mem.eql(u8, "emission", entry.key_ptr.*)) {
                material.emission_map = readTexture(alloc, entry.value_ptr.*, .Emission, self.tex, resources);
            } else if (std.mem.eql(u8, "emittance", entry.key_ptr.*)) {
                loadEmittance(alloc, entry.value_ptr.*, self.tex, resources, &material.super.emittance);
            } else if (std.mem.eql(u8, "roughness", entry.key_ptr.*)) {
                material.setRoughness(readValue(f32, alloc, entry.value_ptr.*, material.roughness, .Roughness, self.tex, resources));
            } else if (std.mem.eql(u8, "surface", entry.key_ptr.*)) {
                material.surface_map = readTexture(alloc, entry.value_ptr.*, .Surface, self.tex, resources);
            } else if (std.mem.eql(u8, "checkers", entry.key_ptr.*)) {
                var checkers: [2]Vec4f = .{ @splat(4, @as(f32, 0.0)), @splat(4, @as(f32, 0.0)) };
                var checkers_scale: f32 = 0.0;

                var citer = entry.value_ptr.Object.iterator();
                while (citer.next()) |cn| {
                    if (std.mem.eql(u8, "scale", cn.key_ptr.*)) {
                        checkers_scale = json.readFloat(f32, cn.value_ptr.*);
                    } else if (std.mem.eql(u8, "colors", cn.key_ptr.*)) {
                        checkers[0] = readColor(cn.value_ptr.Array.items[0]);
                        checkers[1] = readColor(cn.value_ptr.Array.items[1]);
                    }
                }

                material.setCheckers(checkers[0], checkers[1], checkers_scale);
            } else if (std.mem.eql(u8, "metal_preset", entry.key_ptr.*)) {
                const eta_k = metal.iorAndAbsorption(entry.value_ptr.String);
                material.setColor(MappedValue(Vec4f).init(fresnel.conductor(eta_k[0], eta_k[1], 1.0)));
                material.metallic = 1.0;
            } else if (std.mem.eql(u8, "attenuation_color", entry.key_ptr.*)) {
                attenuation_color = readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "subsurface_color", entry.key_ptr.*)) {
                subsurface_color = readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "anisotropy_rotation", entry.key_ptr.*)) {
                material.setRotation(readValue(f32, alloc, entry.value_ptr.*, material.rotation, .Roughness, self.tex, resources));
            } else if (std.mem.eql(u8, "anisotropy", entry.key_ptr.*)) {
                material.anisotropy = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "metallic", entry.key_ptr.*)) {
                material.metallic = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "ior", entry.key_ptr.*)) {
                material.super.ior = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "two_sided", entry.key_ptr.*)) {
                material.super.setTwoSided(json.readBool(entry.value_ptr.*));
            } else if (std.mem.eql(u8, "thickness", entry.key_ptr.*)) {
                material.thickness = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "attenuation_distance", entry.key_ptr.*)) {
                material.super.attenuation_distance = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "volumetric_anisotropy", entry.key_ptr.*)) {
                material.super.volumetric_anisotropy = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
                material.super.sampler_key = readSamplerKey(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "coating", entry.key_ptr.*)) {
                var coating_color = @splat(4, @as(f32, 1.0));
                var coating_attenuation_distance: f32 = 0.1;

                var citer = entry.value_ptr.Object.iterator();
                while (citer.next()) |c| {
                    if (std.mem.eql(u8, "color", c.key_ptr.*)) {
                        coating_color = readColor(c.value_ptr.*);
                    } else if (std.mem.eql(u8, "attenuation_distance", c.key_ptr.*)) {
                        coating_attenuation_distance = json.readFloat(f32, c.value_ptr.*);
                    } else if (std.mem.eql(u8, "ior", c.key_ptr.*)) {
                        material.coating_ior = json.readFloat(f32, c.value_ptr.*);
                    } else if (std.mem.eql(u8, "normal", c.key_ptr.*)) {
                        material.coating_normal_map = readTexture(alloc, c.value_ptr.*, .Normal, self.tex, resources);
                    } else if (std.mem.eql(u8, "roughness", c.key_ptr.*)) {
                        material.setCoatingRoughness(readValue(
                            f32,
                            alloc,
                            c.value_ptr.*,
                            material.coating_roughness,
                            .Roughness,
                            self.tex,
                            resources,
                        ));
                    } else if (std.mem.eql(u8, "thickness", c.key_ptr.*)) {
                        material.setCoatingThickness(readValue(
                            f32,
                            alloc,
                            c.value_ptr.*,
                            material.coating_thickness,
                            .Roughness,
                            self.tex,
                            resources,
                        ));
                    }
                }

                material.setCoatingAttenuation(coating_color, coating_attenuation_distance);
            } else if (std.mem.eql(u8, "flakes", entry.key_ptr.*)) {
                var citer = entry.value_ptr.Object.iterator();
                while (citer.next()) |c| {
                    if (std.mem.eql(u8, "color", c.key_ptr.*)) {
                        material.flakes_color = readColor(c.value_ptr.*);
                    } else if (std.mem.eql(u8, "coverage", c.key_ptr.*)) {
                        material.flakes_coverage = json.readFloat(f32, c.value_ptr.*);
                    } else if (std.mem.eql(u8, "roughness", c.key_ptr.*)) {
                        material.setFlakesRoughness(json.readFloat(f32, c.value_ptr.*));
                    } else if (std.mem.eql(u8, "size", c.key_ptr.*)) {
                        material.flakes_size = json.readFloat(f32, c.value_ptr.*);
                    }
                }
            }
        }

        material.super.setVolumetric(
            attenuation_color,
            subsurface_color,
            material.super.attenuation_distance,
            material.super.volumetric_anisotropy,
        );
    }

    fn loadVolumetric(self: Provider, alloc: Allocator, value: std.json.Value, resources: *Resources) !Material {
        var material = mat.Volumetric.init();

        self.updateVolumetric(alloc, &material, value, resources);

        return Material{ .Volumetric = material };
    }

    fn updateVolumetric(self: Provider, alloc: Allocator, material: *mat.Volumetric, value: std.json.Value, resources: *Resources) void {
        var color = @splat(4, @as(f32, 0.5));

        var attenuation_color = @splat(4, @as(f32, 1.0));
        var subsurface_color = @splat(4, @as(f32, 0.0));

        var use_attenuation_color = false;
        var use_subsurface_color = false;

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "density", entry.key_ptr.*)) {
                material.density_map = readTexture(alloc, entry.value_ptr.*, .Roughness, self.tex, resources);
            } else if (std.mem.eql(u8, "temperature", entry.key_ptr.*)) {
                material.temperature_map = readTexture(alloc, entry.value_ptr.*, .Roughness, self.tex, resources);
            } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
                material.super.sampler_key = readSamplerKey(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "color", entry.key_ptr.*)) {
                color = readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "emittance", entry.key_ptr.*)) {
                loadEmittance(alloc, entry.value_ptr.*, self.tex, resources, &material.super.emittance);
            } else if (std.mem.eql(u8, "attenuation_color", entry.key_ptr.*)) {
                attenuation_color = readColor(entry.value_ptr.*);
                use_attenuation_color = true;
            } else if (std.mem.eql(u8, "subsurface_color", entry.key_ptr.*)) {
                subsurface_color = readColor(entry.value_ptr.*);
                use_subsurface_color = true;
            } else if (std.mem.eql(u8, "attenuation_distance", entry.key_ptr.*)) {
                material.super.attenuation_distance = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "anisotropy", entry.key_ptr.*)) {
                material.super.volumetric_anisotropy = json.readFloat(f32, entry.value_ptr.*);
            }
        }

        if (!use_attenuation_color) {
            attenuation_color = color;
        }

        if (!use_subsurface_color) {
            subsurface_color = color;
        }

        material.super.setVolumetric(
            attenuation_color,
            subsurface_color,
            material.super.attenuation_distance,
            material.super.volumetric_anisotropy,
        );
    }
};

fn loadEmittance(alloc: Allocator, jvalue: std.json.Value, tex: Provider.Tex, resources: *Resources, emittance: *Emittance) void {
    const quantity = json.readStringMember(jvalue, "quantity", "");

    var color = @splat(4, @as(f32, 1.0));
    if (jvalue.Object.get("spectrum")) |s| {
        color = readColor(s);
    }

    if (jvalue.Object.get("profile")) |p| {
        emittance.profile = readTexture(alloc, p, .Emission, tex, resources);
    }

    const profile_angle = math.radiansToDegrees(emittance.angleFromProfile(resources.scene));

    const value = json.readFloatMember(jvalue, "value", 1.0);
    const cos_a = @cos(math.degreesToRadians(json.readFloatMember(jvalue, "angle", profile_angle)));

    if (std.mem.eql(u8, "Flux", quantity)) {
        emittance.setLuminousFlux(color, value, cos_a);
    } else if (std.mem.eql(u8, "Luminous_intensity", quantity)) {
        emittance.setLuminousIntensity(color, value, cos_a);
    } else if (std.mem.eql(u8, "Luminance", quantity)) {
        emittance.setLuminance(color, value, cos_a);
    } else if (std.mem.eql(u8, "Radiant_intensity", quantity)) {
        emittance.setRadiantIntensity(@splat(4, value) * color, cos_a);
    } else // if (std.mem.eql(u8, "Radiance", quantity))
    {
        emittance.setRadiance(@splat(4, value) * color, cos_a);
    }
}

const TextureDescription = struct {
    filename: ?[]u8 = null,
    id: u32 = rsc.Null,

    swizzle: ?img.Swizzle = null,

    scale: Vec2f = Vec2f{ 1.0, 1.0 },

    invert: bool = false,

    pub fn init(alloc: Allocator, value: std.json.Value) !TextureDescription {
        var desc = TextureDescription{};

        switch (value) {
            .Object => |o| {
                var iter = o.iterator();
                while (iter.next()) |entry| {
                    if (std.mem.eql(u8, "file", entry.key_ptr.*)) {
                        desc.filename = try alloc.dupe(u8, entry.value_ptr.String);
                    } else if (std.mem.eql(u8, "id", entry.key_ptr.*)) {
                        desc.id = json.readUInt(entry.value_ptr.*);
                    } else if (std.mem.eql(u8, "swizzle", entry.key_ptr.*)) {
                        const swizzle = entry.value_ptr.String;

                        if (std.mem.eql(u8, "X", swizzle)) {
                            desc.swizzle = .X;
                        } else if (std.mem.eql(u8, "W", swizzle)) {
                            desc.swizzle = .W;
                        } else if (std.mem.eql(u8, "YX", swizzle)) {
                            desc.swizzle = .YX;
                        } else if (std.mem.eql(u8, "YZ", swizzle)) {
                            desc.swizzle = .YZ;
                        }
                    } else if (std.mem.eql(u8, "scale", entry.key_ptr.*)) {
                        desc.scale = switch (entry.value_ptr.*) {
                            .Array => json.readVec2f(entry.value_ptr.*),
                            else => @splat(2, json.readFloat(f32, entry.value_ptr.*)),
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

    pub fn deinit(self: *TextureDescription, alloc: Allocator) void {
        if (self.filename) |filename| {
            alloc.free(filename);
        }
    }
};

fn readSamplerKey(value: std.json.Value) ts.Key {
    var key = ts.Key{};

    switch (value) {
        .Object => |o| {
            var iter = o.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "filter", entry.key_ptr.*)) {
                    const filter = json.readString(entry.value_ptr.*);

                    if (std.mem.eql(u8, "Nearest", filter)) {
                        key.filter = .Nearest;
                    } else if (std.mem.eql(u8, "Linear", filter)) {
                        key.filter = .Linear;
                    }
                } else if (std.mem.eql(u8, "address", entry.key_ptr.*)) {
                    switch (entry.value_ptr.*) {
                        .Array => |a| {
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

fn mapColor(color: Vec4f) Vec4f {
    return spectrum.sRGBtoAP1(color);
}

fn readColor(value: std.json.Value) Vec4f {
    return switch (value) {
        .Array => mapColor(json.readVec4f3(value)),
        .Integer => |i| mapColor(@splat(4, @intToFloat(f32, i))),
        .Float => |f| mapColor(@splat(4, @floatCast(f32, f))),
        .Object => |o| {
            var rgb = @splat(4, @as(f32, 0.0));
            var linear = true;

            var iter = o.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "sRGB", entry.key_ptr.*)) {
                    rgb = readColor(entry.value_ptr.*);
                } else if (std.mem.eql(u8, "temperature", entry.key_ptr.*)) {
                    const temperature = json.readFloat(f32, entry.value_ptr.*);
                    rgb = spectrum.blackbody(std.math.max(800.0, temperature));
                } else if (std.mem.eql(u8, "linear", entry.key_ptr.*)) {
                    linear = json.readBool(entry.value_ptr.*);
                }
            }

            if (!linear) {
                rgb = spectrum.linearToGamma_sRGB3(rgb);
            }

            return mapColor(rgb);
        },
        else => @splat(4, @as(f32, 0.0)),
    };
}

fn readTexture(
    alloc: Allocator,
    value: std.json.Value,
    usage: TexUsage,
    tex: Provider.Tex,
    resources: *Resources,
) Texture {
    var desc = TextureDescription.init(alloc, value) catch return .{};
    defer desc.deinit(alloc);

    return createTexture(alloc, desc, usage, tex, resources);
}

fn createTexture(
    alloc: Allocator,
    desc: TextureDescription,
    usage: TexUsage,
    tex: Provider.Tex,
    resources: *Resources,
) Texture {
    if (tex == .No or (tex == .DWIM and usage != .Emission)) {
        return .{};
    }

    if (desc.filename) |filename| {
        var options: Variants = .{};
        defer options.deinit(alloc);
        options.set(alloc, "usage", usage) catch {};

        if (desc.invert) {
            options.set(alloc, "invert", true) catch {};
        }

        if (desc.swizzle) |swizzle| {
            options.set(alloc, "swizzle", swizzle) catch {};
        }

        return tx.Provider.loadFile(alloc, filename, options, desc.scale, resources) catch |e| {
            log.err("Could not load texture \"{s}\": {}", .{ filename, e });
            return .{};
        };
    } else if (rsc.Null != desc.id) {
        return tx.Provider.createTexture(desc.id, usage, desc.scale, resources) catch |e| {
            log.err("Could not create texture \"{}\": {}", .{ desc.id, e });
            return .{};
        };
    }

    return .{};
}

fn readValue(
    comptime Value: type,
    alloc: Allocator,
    value: std.json.Value,
    default: Value,
    usage: TexUsage,
    tex: Provider.Tex,
    resources: *Resources,
) MappedValue(Value) {
    var result = MappedValue(Value){ .value = default };

    if (Vec4f == Value) {
        switch (value) {
            .Object => {
                var desc = TextureDescription.init(alloc, value) catch return result;
                defer desc.deinit(alloc);

                result.texture = createTexture(alloc, desc, usage, tex, resources);

                if (value.Object.get("value")) |n| {
                    result.value = readColor(n);
                }
            },
            else => result.value = readColor(value),
        }

        return result;
    } else {
        switch (value) {
            .Object => {
                var desc = TextureDescription.init(alloc, value) catch return result;
                defer desc.deinit(alloc);

                result.texture = createTexture(alloc, desc, usage, tex, resources);
                result.value = json.readFloatMember(value, "value", result.value);
            },
            else => result.value = json.readFloat(f32, value),
        }
    }

    return result;
}
