const Tree = @import("tree.zig").Tree;
const tri = @import("../triangle.zig");
const IndexTriangle = tri.IndexTriangle;
const VertexStream = @import("../vertex_stream.zig").VertexStream;
const Reference = @import("../../../bvh/split_candidate.zig").Reference;
const base = @import("base");
usingnamespace base;
// usingnamespace base.math;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const BuilderSAH = struct {
    pub fn init() BuilderSAH {
        return .{};
    }

    pub fn build(
        self: *BuilderSAH,
        alloc: *Allocator,
        tree: *Tree,
        triangles: []const IndexTriangle,
        vertices: VertexStream,
    ) !void {
        _ = self;

        var references = try alloc.alloc(Reference, triangles.len);
        defer alloc.free(references);

        var bounds = math.aabb.empty;

        for (triangles) |t, i| {
            const a = vertices.position(t.i[0]);
            const b = vertices.position(t.i[1]);
            const c = vertices.position(t.i[2]);

            const min = tri.min(a, b, c);
            const max = tri.max(a, b, c);

            references[i].set(min, max, @intCast(u32, i));

            bounds.bounds[0] = bounds.bounds[0].min3(min);
            bounds.bounds[1] = bounds.bounds[1].max3(max);
        }

        tree.box = bounds;
    }
};
