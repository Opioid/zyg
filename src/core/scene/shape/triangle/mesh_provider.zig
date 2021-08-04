const Mesh = @import("mesh.zig").Mesh;
const Shape = @import("../shape.zig").Shape;
const Resources = @import("../../../resource/manager.zig").Manager;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Provider = struct {
    pub fn load(self: Provider, alloc: *Allocator, name: []const u8, resources: *Resources) !Shape {
        _ = self;

        var file = try resources.fs.readStream(name);
        defer file.close();

        const reader = file.reader();

        const buffer = try reader.readAllAlloc(alloc, std.math.maxInt(u64));
        defer alloc.free(buffer);

        var parser = std.json.Parser.init(alloc, false);
        defer parser.deinit();

        var document = try parser.parse(buffer);
        defer document.deinit();

        // const root = document.root;

        // var iter = root.Object.iterator();

        return Shape{ .Mesh = .{} };
    }
};
