const Material = @import("material.zig").Material;
const Resources = @import("../../resource/manager.zig").Manager;

const std = @import("std");
const Allocator = std.mem.Allocator;

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
                return try loadDebug(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "Light", entry.key_ptr.*)) {
                return try loadLight(entry.value_ptr.*);
            }
        }

        return Error.UnknownMaterial;
    }

    fn loadDebug(value: std.json.Value) !Material {
        _ = value;

        return Material{ .Debug = .{} };
    }

    fn loadLight(value: std.json.Value) !Material {
        _ = value;

        return Material{ .Light = .{} };
    }
};
