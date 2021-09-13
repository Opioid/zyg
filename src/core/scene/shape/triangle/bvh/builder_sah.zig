const Tree = @import("tree.zig").Tree;
const tri = @import("../triangle.zig");
const IndexTriangle = tri.IndexTriangle;
const VertexStream = @import("../vertex_stream.zig").VertexStream;
const Reference = @import("../../../bvh/split_candidate.zig").Reference;
const Base = @import("../../../bvh/builder_base.zig").Base;
const base = @import("base");
const math = base.math;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const BuilderSAH = struct {
    super: Base,

    pub fn init(alloc: *Allocator, num_slices: u32, sweep_threshold: u32, max_primitives: u32) !BuilderSAH {
        return BuilderSAH{ .super = try Base.init(alloc, num_slices, sweep_threshold, max_primitives) };
    }

    pub fn deinit(self: *BuilderSAH, alloc: *Allocator) void {
        self.super.deinit(alloc);
    }

    pub fn build(
        self: *BuilderSAH,
        alloc: *Allocator,
        tree: *Tree,
        triangles: []const IndexTriangle,
        vertices: VertexStream,
        threads: *Threads,
    ) !void {
        try self.super.reserve(alloc, @intCast(u32, triangles.len));

        var references = try alloc.alloc(Reference, triangles.len);

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

        try self.super.split(alloc, references, bounds, threads);

        try tree.data.allocateTriangles(alloc, @intCast(u32, self.super.kernel.reference_ids.items.len), vertices);
        self.super.nodes = try tree.allocateNodes(alloc, @intCast(u32, self.super.kernel.build_nodes.items.len));

        var current_triangle: u32 = 0;
        self.super.newNode();
        self.serialize(0, 0, tree, triangles, vertices, &current_triangle);

        std.debug.print("before/after {}/{}\n", .{ triangles.len, self.super.kernel.reference_ids.items.len });
    }

    fn serialize(
        self: *BuilderSAH,
        source_node: u32,
        dest_node: u32,
        tree: *Tree,
        triangles: []const IndexTriangle,
        vertices: VertexStream,
        current_triangle: *u32,
    ) void {
        const node = &self.super.kernel.build_nodes.items[source_node];

        var n = &self.super.nodes[dest_node];

        n.setAABB(node.aabb());

        if (0 == node.numIndices()) {
            const child0 = self.super.currentNodeIndex();

            n.setSplitNode(child0, node.axis());

            self.super.newNode();
            self.super.newNode();

            const source_child0 = node.children();

            self.serialize(source_child0, child0, tree, triangles, vertices, current_triangle);
            self.serialize(source_child0 + 1, child0 + 1, tree, triangles, vertices, current_triangle);
        } else {
            var i = current_triangle.*;
            const num = node.numIndices();

            n.setLeafNode(i, num);

            const ro = node.children();

            var p = ro;
            var end = ro + num;

            while (p < end) : (p += 1) {
                const t = triangles[self.super.kernel.reference_ids.items[p]];
                tree.data.setTriangle(t.i[0], t.i[1], t.i[2], t.part, vertices, i);

                i += 1;
            }

            current_triangle.* = i;
        }
    }
};
