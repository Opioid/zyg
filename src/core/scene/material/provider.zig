const mat = @import("material.zig");
const Material = mat.Material;
const tx = @import("../../image/texture/provider.zig");
const Texture = tx.Texture;
const TexUsage = tx.Usage;
const Resources = @import("../../resource/manager.zig").Manager;
const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
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

    pub fn deinit(self: *Provider, alloc: *Allocator) void {
        _ = self;
        _ = alloc;
    }

    pub fn setSettings(self: *Provider, no_tex: bool) void {
        if (no_tex) {
            self.tex = .No;
        }
    }

    pub fn loadFile(
        self: Provider,
        alloc: *Allocator,
        name: []const u8,
        options: Variants,
        resources: *Resources,
    ) !Material {
        _ = options;

        var stream = try resources.fs.readStream(name);
        defer stream.deinit();

        const buffer = try stream.reader.unbuffered_reader.readAllAlloc(alloc, std.math.maxInt(u64));
        defer alloc.free(buffer);

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
        return Material{ .Debug = .{ .super = .{ .mask = Texture{}, .properties = .{} } } };
    }

    fn loadMaterial(self: Provider, alloc: *Allocator, value: std.json.Value, resources: *Resources) !Material {
        _ = self;

        const rendering_node = value.Object.get("rendering") orelse {
            return Error.NoRenderNode;
        };

        var iter = rendering_node.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "Debug", entry.key_ptr.*)) {
                return Material{ .Debug = .{} };
            } else if (std.mem.eql(u8, "Glass", entry.key_ptr.*)) {
                return try self.loadGlass(alloc, entry.value_ptr.*, resources);
            } else if (std.mem.eql(u8, "Light", entry.key_ptr.*)) {
                return try self.loadLight(alloc, entry.value_ptr.*, resources);
            } else if (std.mem.eql(u8, "Substitute", entry.key_ptr.*)) {
                return try self.loadSubstitute(alloc, entry.value_ptr.*, resources);
            }
        }

        return Error.UnknownMaterial;
    }

    fn loadGlass(self: Provider, alloc: *Allocator, value: std.json.Value, resources: *Resources) !Material {
        var mask = Texture{};

        var thickness: f32 = 0.0;

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "mask", entry.key_ptr.*)) {
                mask = readTexture(alloc, entry.value_ptr.*, TexUsage.Mask, self.tex, resources);
            } else if (std.mem.eql(u8, "thickness", entry.key_ptr.*)) {
                thickness = json.readFloat(entry.value_ptr.*);
            }
        }

        var material = mat.Glass{};

        material.super.mask = mask;

        material.thickness = thickness;

        return Material{ .Glass = material };
    }

    fn loadLight(self: Provider, alloc: *Allocator, value: std.json.Value, resources: *Resources) !Material {
        var emission = MappedValue(Vec4f).init(@splat(4, @as(f32, 10.0)));

        var mask = Texture{};

        var two_sided = false;

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "mask", entry.key_ptr.*)) {
                mask = readTexture(alloc, entry.value_ptr.*, TexUsage.Mask, self.tex, resources);
            } else if (std.mem.eql(u8, "emission", entry.key_ptr.*)) {
                emission.read(alloc, entry.value_ptr.*, TexUsage.Color, self.tex, resources);
            } else if (std.mem.eql(u8, "two_sided", entry.key_ptr.*)) {
                two_sided = json.readBool(entry.value_ptr.*);
            }
        }

        var material = mat.Light.init(two_sided);

        material.super.mask = mask;

        material.emittance.setRadiance(emission.value);

        return Material{ .Light = material };
    }

    fn loadSubstitute(self: Provider, alloc: *Allocator, value: std.json.Value, resources: *Resources) !Material {
        var color = MappedValue(Vec4f).init(@splat(4, @as(f32, 0.5)));

        var mask = Texture{};
        var normal_map = Texture{};

        var two_sided = false;

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "mask", entry.key_ptr.*)) {
                mask = readTexture(alloc, entry.value_ptr.*, TexUsage.Mask, self.tex, resources);
            } else if (std.mem.eql(u8, "color", entry.key_ptr.*)) {
                color.read(alloc, entry.value_ptr.*, TexUsage.Color, self.tex, resources);
            } else if (std.mem.eql(u8, "normal", entry.key_ptr.*)) {
                normal_map = readTexture(alloc, entry.value_ptr.*, TexUsage.Normal, self.tex, resources);
            } else if (std.mem.eql(u8, "two_sided", entry.key_ptr.*)) {
                two_sided = json.readBool(entry.value_ptr.*);
            }
        }

        var material = mat.Substitute.init(two_sided);

        material.super.mask = mask;
        material.super.color_map = color.texture;

        material.normal_map = normal_map;

        material.color = color.value;

        return Material{ .Substitute = material };
    }
};

const TextureDescription = struct {
    filename: ?[]u8 = null,

    pub fn init(alloc: *Allocator, value: std.json.Value) !TextureDescription {
        var desc = TextureDescription{};

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "file", entry.key_ptr.*)) {
                const string = entry.value_ptr.String;
                desc.filename = try alloc.alloc(u8, string.len);
                if (desc.filename) |filename| {
                    std.mem.copy(u8, filename, string);
                }
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

fn mapColor(color: Vec4f) Vec4f {
    return spectrum.sRGBtoAP1(color);
}

fn readColor(value: std.json.Value) Vec4f {
    return switch (value) {
        .Array => mapColor(json.readVec4f3(value)),
        .Float => |f| mapColor(@splat(4, @floatCast(f32, f))),
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
            } else unreachable;
        }
    };
}

fn createTexture(
    alloc: *Allocator,
    desc: TextureDescription,
    usage: TexUsage,
    tex: Provider.Tex,
    resources: *Resources,
) Texture {
    if (tex == .No) {
        return .{};
    }

    if (desc.filename) |filename| {
        var options: Variants = .{};
        defer options.deinit(alloc);
        options.set(alloc, "usage", usage) catch {};
        return tx.Provider.loadFile(alloc, filename, options, resources) catch .{};
    }

    return .{};
}
