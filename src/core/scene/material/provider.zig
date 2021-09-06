const mat = @import("material.zig");
const Material = mat.Material;
const Resources = @import("../../resource/manager.zig").Manager;
const base = @import("base");
usingnamespace base;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

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
        value: Value = undefined,

        const Self = @This();

        pub fn read(value: std.json.Value) Self {
            if (Vec4f == Value) {
                return switch (value) {
                    else => .{ .value = readColor(value) },
                };
            } else unreachable;
        }
    };
}

pub const Provider = struct {
    const Error = error{
        NoRenderNode,
        UnknownMaterial,
    };

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
        _ = alloc;
        _ = resources;

        const rendering_node = value.Object.get("rendering") orelse {
            return Error.NoRenderNode;
        };

        var iter = rendering_node.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "Debug", entry.key_ptr.*)) {
                return Material{ .Debug = .{} };
            } else if (std.mem.eql(u8, "Light", entry.key_ptr.*)) {
                return try loadLight(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "Substitute", entry.key_ptr.*)) {
                return try loadSubstitute(entry.value_ptr.*);
            }
        }

        return Error.UnknownMaterial;
    }

    fn loadLight(value: std.json.Value) !Material {
        var emission: MappedValue(Vec4f) = .{ .value = Vec4f.init1(10.0) };

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "emission", entry.key_ptr.*)) {
                //     color.value = readColor(entry.value_ptr.*);
                emission = MappedValue(Vec4f).read(entry.value_ptr.*);
            }
        }

        var material = mat.Light{};

        material.emittance.setRadiance(emission.value);

        return Material{ .Light = material };
    }

    fn loadSubstitute(value: std.json.Value) !Material {
        var color: MappedValue(Vec4f) = .{ .value = Vec4f.init1(0.5) };

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "color", entry.key_ptr.*)) {
                //     color.value = readColor(entry.value_ptr.*);
                color = MappedValue(Vec4f).read(entry.value_ptr.*);
            }
        }

        var material = mat.Substitute{};

        material.color = color.value;

        return Material{ .Substitute = material };
    }
};
