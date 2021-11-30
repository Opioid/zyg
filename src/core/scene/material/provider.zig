const mat = @import("material.zig");
const Material = mat.Material;
const metal = @import("metal_presets.zig");
const fresnel = @import("fresnel.zig");
const img = @import("../../image/image.zig");
const tx = @import("../../image/texture/provider.zig");
const Texture = tx.Texture;
const TexUsage = tx.Usage;
const ts = @import("../../image/texture/sampler.zig");
const Resources = @import("../../resource/manager.zig").Manager;
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

    pub fn deinit(self: *Provider, alloc: *Allocator) void {
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
        alloc: *Allocator,
        name: []const u8,
        options: Variants,
        resources: *Resources,
    ) !Material {
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

        return try self.loadMaterial(alloc, root, resources);
    }

    pub fn loadData(
        self: Provider,
        alloc: *Allocator,
        data: usize,
        options: Variants,
        resources: *Resources,
    ) !Material {
        _ = options;

        const value = @intToPtr(*std.json.Value, data);

        return try self.loadMaterial(alloc, value.*, resources);
    }

    pub fn createFallbackMaterial() Material {
        return Material{ .Debug = mat.Debug.init() };
    }

    fn loadMaterial(self: Provider, alloc: *Allocator, value: std.json.Value, resources: *Resources) !Material {
        const rendering_node = value.Object.get("rendering") orelse {
            return Error.NoRenderNode;
        };

        var iter = rendering_node.Object.iterator();
        while (iter.next()) |entry| {
            if (self.force_debug_material) {
                if (std.mem.eql(u8, "Light", entry.key_ptr.*)) {
                    return try self.loadLight(alloc, entry.value_ptr.*, resources);
                } else {
                    return createFallbackMaterial();
                }
            } else {
                if (std.mem.eql(u8, "Debug", entry.key_ptr.*)) {
                    return Material{ .Debug = mat.Debug.init() };
                } else if (std.mem.eql(u8, "Glass", entry.key_ptr.*)) {
                    return try self.loadGlass(alloc, entry.value_ptr.*, resources);
                } else if (std.mem.eql(u8, "Light", entry.key_ptr.*)) {
                    return try self.loadLight(alloc, entry.value_ptr.*, resources);
                } else if (std.mem.eql(u8, "Substitute", entry.key_ptr.*)) {
                    return try self.loadSubstitute(alloc, entry.value_ptr.*, resources);
                } else if (std.mem.eql(u8, "Volumetric", entry.key_ptr.*)) {
                    return try self.loadVolumetric(alloc, entry.value_ptr.*, resources);
                }
            }
        }

        return Error.UnknownMaterial;
    }

    fn loadGlass(self: Provider, alloc: *Allocator, value: std.json.Value, resources: *Resources) !Material {
        var sampler_key = ts.Key{};

        var roughness = MappedValue(f32).init(0.0);

        var mask = Texture{};
        var normal_map = Texture{};

        var attenuation_color = @splat(4, @as(f32, 1.0));

        var attenuation_distance: f32 = 1.0;
        var ior: f32 = 1.46;
        var abbe: f32 = 0.0;
        var thickness: f32 = 0.0;

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "mask", entry.key_ptr.*)) {
                mask = readTexture(alloc, entry.value_ptr.*, .Mask, self.tex, resources);
            } else if (std.mem.eql(u8, "normal", entry.key_ptr.*)) {
                normal_map = readTexture(alloc, entry.value_ptr.*, .Normal, self.tex, resources);
            } else if (std.mem.eql(u8, "color", entry.key_ptr.*) or std.mem.eql(u8, "attenuation_color", entry.key_ptr.*)) {
                attenuation_color = readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "attenuation_distance", entry.key_ptr.*)) {
                attenuation_distance = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "roughness", entry.key_ptr.*)) {
                roughness.read(alloc, entry.value_ptr.*, .Roughness, self.tex, resources);
            } else if (std.mem.eql(u8, "ior", entry.key_ptr.*)) {
                ior = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "abbe", entry.key_ptr.*)) {
                abbe = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "thickness", entry.key_ptr.*)) {
                thickness = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
                sampler_key = readSamplerKey(entry.value_ptr.*);
            }
        }

        var material = mat.Glass.init(sampler_key);

        material.super.mask = mask;
        material.normal_map = normal_map;
        material.roughness_map = roughness.texture;

        material.super.setVolumetric(attenuation_color, @splat(4, @as(f32, 0.0)), attenuation_distance, 0.0);
        material.super.ior = ior;
        material.setRoughness(roughness.value);
        material.thickness = thickness;
        material.abbe = abbe;

        return Material{ .Glass = material };
    }

    fn loadLight(self: Provider, alloc: *Allocator, light_value: std.json.Value, resources: *Resources) !Material {
        var sampler_key = ts.Key{};

        var quantity: []const u8 = undefined;

        var emission = MappedValue(Vec4f).init(@splat(4, @as(f32, 10.0)));

        var mask = Texture{};

        var color = @splat(4, @as(f32, 1.0));

        var value: f32 = 1.0;
        var emission_factor: f32 = 1.0;

        var two_sided = false;

        var iter = light_value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "mask", entry.key_ptr.*)) {
                mask = readTexture(alloc, entry.value_ptr.*, .Mask, self.tex, resources);
            } else if (std.mem.eql(u8, "emission", entry.key_ptr.*)) {
                emission.read(alloc, entry.value_ptr.*, .Emission, self.tex, resources);
            } else if (std.mem.eql(u8, "emittance", entry.key_ptr.*)) {
                quantity = json.readStringMember(entry.value_ptr.*, "quantity", "");

                if (entry.value_ptr.Object.get("spectrum")) |s| {
                    color = readColor(s);
                }

                value = json.readFloatMember(entry.value_ptr.*, "value", value);
            } else if (std.mem.eql(u8, "emission_factor", entry.key_ptr.*)) {
                emission_factor = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "two_sided", entry.key_ptr.*)) {
                two_sided = json.readBool(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
                sampler_key = readSamplerKey(entry.value_ptr.*);
            }
        }

        var material = mat.Light.init(sampler_key, two_sided);

        material.super.mask = mask;
        material.emission_map = emission.texture;

        if (std.mem.eql(u8, "Flux", quantity)) {
            material.emittance.setLuminousFlux(color, value);
        } else if (std.mem.eql(u8, "Intensity", quantity)) {
            material.emittance.setLuminousIntensity(color, value);
        } else if (std.mem.eql(u8, "Luminance", quantity)) {
            material.emittance.setLuminance(color, value);
        } else {
            material.emittance.setRadiance(emission.value);
        }

        material.emission_factor = emission_factor;
        material.super.ior = 1.5;

        return Material{ .Light = material };
    }

    fn loadSubstitute(self: Provider, alloc: *Allocator, value: std.json.Value, resources: *Resources) !Material {
        var sampler_key = ts.Key{};

        var color = MappedValue(Vec4f).init(@splat(4, @as(f32, 0.5)));
        var emission = MappedValue(Vec4f).init(@splat(4, @as(f32, 0.0)));
        var roughness = MappedValue(f32).init(0.8);
        var rotation = MappedValue(f32).init(0.0);

        var mask = Texture{};
        var normal_map = Texture{};

        var attenuation_color = @splat(4, @as(f32, 0.0));
        var subsurface_color = @splat(4, @as(f32, 0.0));

        var checkers: [2]Vec4f = undefined;
        var checkers_scale: f32 = 0.0;

        var metallic: f32 = 0.0;
        var ior: f32 = 1.46;
        var anisotropy: f32 = 0.0;
        var emission_factor: f32 = 1.0;
        var thickness: f32 = 0.0;
        var attenuation_distance: f32 = 0.0;
        var volumetric_anisotropy: f32 = 0.0;

        var coating: CoatingDescription = .{};

        var two_sided = false;

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "mask", entry.key_ptr.*)) {
                mask = readTexture(alloc, entry.value_ptr.*, .Mask, self.tex, resources);
            } else if (std.mem.eql(u8, "color", entry.key_ptr.*)) {
                color.read(alloc, entry.value_ptr.*, .Color, self.tex, resources);
            } else if (std.mem.eql(u8, "normal", entry.key_ptr.*)) {
                normal_map = readTexture(alloc, entry.value_ptr.*, .Normal, self.tex, resources);
            } else if (std.mem.eql(u8, "emission", entry.key_ptr.*)) {
                emission.read(alloc, entry.value_ptr.*, .Emission, self.tex, resources);
            } else if (std.mem.eql(u8, "roughness", entry.key_ptr.*)) {
                roughness.read(alloc, entry.value_ptr.*, .Roughness, self.tex, resources);
            } else if (std.mem.eql(u8, "surface", entry.key_ptr.*)) {
                roughness.texture = readTexture(alloc, entry.value_ptr.*, .Surface, self.tex, resources);
            } else if (std.mem.eql(u8, "checkers", entry.key_ptr.*)) {
                var citer = entry.value_ptr.Object.iterator();
                while (citer.next()) |cn| {
                    if (std.mem.eql(u8, "scale", cn.key_ptr.*)) {
                        checkers_scale = json.readFloat(f32, cn.value_ptr.*);
                    } else if (std.mem.eql(u8, "colors", cn.key_ptr.*)) {
                        checkers[0] = readColor(cn.value_ptr.Array.items[0]);
                        checkers[1] = readColor(cn.value_ptr.Array.items[1]);
                    }
                }
            } else if (std.mem.eql(u8, "metal_preset", entry.key_ptr.*)) {
                const eta_k = metal.iorAndAbsorption(entry.value_ptr.String);
                color.value = fresnel.conductor(eta_k[0], eta_k[1], 1.0);
                metallic = 1.0;
            } else if (std.mem.eql(u8, "attenuation_color", entry.key_ptr.*)) {
                attenuation_color = readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "subsurface_color", entry.key_ptr.*)) {
                subsurface_color = readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "anisotropy_rotation", entry.key_ptr.*)) {
                rotation.read(alloc, entry.value_ptr.*, .Roughness, self.tex, resources);
            } else if (std.mem.eql(u8, "anisotropy", entry.key_ptr.*)) {
                anisotropy = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "metallic", entry.key_ptr.*)) {
                metallic = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "ior", entry.key_ptr.*)) {
                ior = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "two_sided", entry.key_ptr.*)) {
                two_sided = json.readBool(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "emission_factor", entry.key_ptr.*)) {
                emission_factor = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "thickness", entry.key_ptr.*)) {
                thickness = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "attenuation_distance", entry.key_ptr.*)) {
                attenuation_distance = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "volumetric_anisotropy", entry.key_ptr.*)) {
                volumetric_anisotropy = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
                sampler_key = readSamplerKey(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "coating", entry.key_ptr.*)) {
                coating.read(alloc, entry.value_ptr.*, self.tex, resources);
            }
        }

        var material = mat.Substitute.init(sampler_key, two_sided);

        material.super.mask = mask;
        material.super.color_map = color.texture;
        material.normal_map = normal_map;
        material.surface_map = roughness.texture;
        material.emission_map = emission.texture;

        material.color = color.value;
        material.super.emission = emission.value;

        material.emission_factor = emission_factor;
        material.setRoughness(roughness.value, anisotropy);
        material.rotation = rotation.value;
        material.super.ior = ior;
        material.metallic = metallic;
        material.setTranslucency(thickness, attenuation_distance);

        material.super.setVolumetric(
            attenuation_color,
            subsurface_color,
            attenuation_distance,
            volumetric_anisotropy,
        );

        if (checkers_scale > 0.0) {
            material.setCheckers(checkers[0], checkers[1], checkers_scale);
        }

        if (coating.thickness.texture.isValid() or coating.thickness.value > 0.0) {
            material.coating.normal_map = coating.normal_map;
            material.coating.thickness_map = coating.thickness.texture;
            material.coating.setAttenuation(coating.color, coating.attenuation_distance);
            material.coating.thickness = coating.thickness.value;
            material.coating.ior = coating.ior;
            material.coating.setRoughness(coating.roughness);
        }

        return Material{ .Substitute = material };
    }

    fn loadVolumetric(self: Provider, alloc: *Allocator, value: std.json.Value, resources: *Resources) !Material {
        _ = self;
        _ = alloc;
        _ = resources;

        var sampler_key = ts.Key{};

        var color = @splat(4, @as(f32, 5.0));

        var attenuation_color = @splat(4, @as(f32, 1.0));
        var subsurface_color = @splat(4, @as(f32, 0.0));

        var use_attenuation_color = false;
        var use_subsurface_color = false;

        var attenuation_distance: f32 = 1.0;
        var anisotropy: f32 = 0.0;

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "sampler", entry.key_ptr.*)) {
                sampler_key = readSamplerKey(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "color", entry.key_ptr.*)) {
                color = readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "attenuation_color", entry.key_ptr.*)) {
                attenuation_color = readColor(entry.value_ptr.*);
                use_attenuation_color = true;
            } else if (std.mem.eql(u8, "subsurface_color", entry.key_ptr.*)) {
                subsurface_color = readColor(entry.value_ptr.*);
                use_subsurface_color = true;
            } else if (std.mem.eql(u8, "attenuation_distance", entry.key_ptr.*)) {
                attenuation_distance = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "anisotropy", entry.key_ptr.*)) {
                anisotropy = json.readFloat(f32, entry.value_ptr.*);
            }
        }

        if (!use_attenuation_color) {
            attenuation_color = color;
        }

        if (!use_subsurface_color) {
            subsurface_color = color;
        }

        var material = mat.Volumetric.init(sampler_key);

        material.super.setVolumetric(attenuation_color, subsurface_color, attenuation_distance, anisotropy);

        return Material{ .Volumetric = material };
    }
};

const TextureDescription = struct {
    filename: ?[]u8 = null,

    swizzle: ?img.Swizzle = null,

    scale: Vec2f = Vec2f{ 1.0, 1.0 },

    invert: bool = false,

    pub fn init(alloc: *Allocator, value: std.json.Value) !TextureDescription {
        var desc = TextureDescription{};

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "file", entry.key_ptr.*)) {
                const string = entry.value_ptr.String;
                const filename = try alloc.alloc(u8, string.len);
                std.mem.copy(u8, filename, string);
                desc.filename = filename;
            } else if (std.mem.eql(u8, "swizzle", entry.key_ptr.*)) {
                const swizzle = entry.value_ptr.String;

                if (std.mem.eql(u8, "X", swizzle)) {
                    desc.swizzle = .X;
                } else if (std.mem.eql(u8, "W", swizzle)) {
                    desc.swizzle = .W;
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

        return desc;
    }

    pub fn deinit(self: *TextureDescription, alloc: *Allocator) void {
        if (self.filename) |filename| {
            alloc.free(filename);
        }
    }
};

fn readSamplerKey(value: std.json.Value) ts.Key {
    var key = ts.Key{};

    var iter = value.Object.iterator();
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
                    rgb = spectrum.blackbody(@maximum(800.0, temperature));
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
    alloc: *Allocator,
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
    alloc: *Allocator,
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

        return tx.Provider.loadFile(alloc, filename, options, desc.scale, resources) catch .{};
    }

    return .{};
}

fn MappedValue(comptime Value: type) type {
    return struct {
        texture: Texture = .{},

        value: Value,

        const Self = @This();

        pub fn init(value: Value) Self {
            return .{ .value = value };
        }

        pub fn read(
            self: *Self,
            alloc: *Allocator,
            value: std.json.Value,
            usage: TexUsage,
            tex: Provider.Tex,
            resources: *Resources,
        ) void {
            if (Vec4f == Value) {
                switch (value) {
                    .Object => {
                        var desc = TextureDescription.init(alloc, value) catch return;
                        defer desc.deinit(alloc);

                        self.texture = createTexture(alloc, desc, usage, tex, resources);

                        if (value.Object.get("value")) |n| {
                            self.value = readColor(n);
                        }
                    },
                    else => self.value = readColor(value),
                }
            } else {
                switch (value) {
                    .Object => {
                        var desc = TextureDescription.init(alloc, value) catch return;
                        defer desc.deinit(alloc);

                        self.texture = createTexture(alloc, desc, usage, tex, resources);

                        self.value = json.readFloatMember(value, "value", self.value);
                    },
                    else => self.value = json.readFloat(f32, value),
                }
            }
        }
    };
}

const CoatingDescription = struct {
    thickness: MappedValue(f32) = MappedValue(f32).init(0.0),

    normal_map: Texture = .{},

    color: Vec4f = @splat(4, @as(f32, 1.0)),

    attenuation_distance: f32 = 0.1,
    ior: f32 = 1.5,
    roughness: f32 = 0.2,

    const Self = @This();

    pub fn read(
        self: *Self,
        alloc: *Allocator,
        value: std.json.Value,
        tex: Provider.Tex,
        resources: *Resources,
    ) void {
        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "color", entry.key_ptr.*)) {
                self.color = readColor(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "attenuation_distance", entry.key_ptr.*)) {
                self.attenuation_distance = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "ior", entry.key_ptr.*)) {
                self.ior = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "normal", entry.key_ptr.*)) {
                self.normal_map = readTexture(alloc, entry.value_ptr.*, .Normal, tex, resources);
            } else if (std.mem.eql(u8, "roughness", entry.key_ptr.*)) {
                self.roughness = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "thickness", entry.key_ptr.*)) {
                self.thickness.read(alloc, entry.value_ptr.*, .Roughness, tex, resources);
            }
        }
    }
};
