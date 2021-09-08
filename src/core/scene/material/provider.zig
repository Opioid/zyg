const mat = @import("material.zig");
const Material = mat.Material;
const tx = @import("../../image/texture/provider.zig");
const Texture = tx.Texture;
const Resources = @import("../../resource/manager.zig").Manager;
const base = @import("base");
usingnamespace base;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

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
        .Float => |f| mapColor(Vec4f.init1(@floatCast(f32, f))),
        else => Vec4f.init1(0.0),
    };
}

fn MappedValue(comptime Value: type) type {
    return struct {
        texture: Texture = .{},

        value: Value,

        const Self = @This();

        pub fn init(value: Value) Self {
            return .{ .value = value };
        }

        pub fn read(self: *Self, alloc: *Allocator, value: std.json.Value, resources: *Resources) !void {
            if (Vec4f == Value) {
                switch (value) {
                    .Object => {
                        var desc = try TextureDescription.init(alloc, value);
                        defer desc.deinit(alloc);

                        self.texture = createTexture(alloc, desc, resources);

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

fn createTexture(alloc: *Allocator, desc: TextureDescription, resources: *Resources) Texture {
    if (desc.filename) |filename| {
        return tx.Provider.loadFile(alloc, filename, resources) catch .{};
    }

    return .{};
}

pub const Provider = struct {
    const Error = error{
        NoRenderNode,
        UnknownMaterial,
    };

    pub fn deinit(self: *Provider, alloc: *Allocator) void {
        _ = self;
        _ = alloc;
    }

    pub fn loadFile(self: Provider, alloc: *Allocator, name: []const u8, resources: *Resources) !Material {
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

    pub fn loadData(self: Provider, alloc: *Allocator, data: usize, resources: *Resources) !Material {
        const value = @intToPtr(*std.json.Value, data);

        return try self.loadMaterial(alloc, value.*, resources);
    }

    pub fn createFallbackMaterial() Material {
        return Material{ .Debug = .{} };
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
            } else if (std.mem.eql(u8, "Light", entry.key_ptr.*)) {
                return try loadLight(alloc, entry.value_ptr.*, resources);
            } else if (std.mem.eql(u8, "Substitute", entry.key_ptr.*)) {
                return try loadSubstitute(alloc, entry.value_ptr.*, resources);
            }
        }

        return Error.UnknownMaterial;
    }

    fn loadLight(alloc: *Allocator, value: std.json.Value, resources: *Resources) !Material {
        var emission = MappedValue(Vec4f).init(Vec4f.init1(10.0));

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "emission", entry.key_ptr.*)) {
                try emission.read(alloc, entry.value_ptr.*, resources);
            }
        }

        var material = mat.Light{};

        material.emittance.setRadiance(emission.value);

        return Material{ .Light = material };
    }

    fn loadSubstitute(alloc: *Allocator, value: std.json.Value, resources: *Resources) !Material {
        var color = MappedValue(Vec4f).init(Vec4f.init1(0.5));

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "color", entry.key_ptr.*)) {
                try color.read(alloc, entry.value_ptr.*, resources);
            }
        }

        var material = mat.Substitute{};

        material.super.color_map = color.texture;

        material.color = color.value;

        return Material{ .Substitute = material };
    }
};
