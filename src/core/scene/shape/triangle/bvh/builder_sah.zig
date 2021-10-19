const Tree = @import("tree.zig").Tree;
const tri = @import("../triangle.zig");
const IndexTriangle = tri.IndexTriangle;
const VertexStream = @import("../vertex_stream.zig").VertexStream;
const Reference = @import("../../../bvh/split_candidate.zig").Reference;
const Base = @import("../../../bvh/builder_base.zig").Base;
const base = @import("base");
const math = base.math;
const AABB = math.AABB;
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

        var context = ReferencesContext{
            .references = try alloc.alloc(Reference, triangles.len),
            .aabbs = try alloc.alloc(AABB, threads.numThreads()),
            .triangles = triangles.ptr,
            .vertices = &vertices,
        };

        const num = threads.runRange(&context, ReferencesContext.run, 0, @intCast(u32, triangles.len));

        var bounds = math.aabb.empty;
        for (context.aabbs[0..num]) |b| {
            bounds.mergeAssign(b);
        }

        alloc.free(context.aabbs);

        try self.super.split(alloc, context.references, bounds, threads);

        try tree.data.allocateTriangles(alloc, self.super.numReferenceIds(), vertices);
        try tree.allocateNodes(alloc, self.super.numBuildNodes());

        var current_triangle: u32 = 0;
        self.super.newNode();
        self.serialize(0, 0, tree, triangles, vertices, &current_triangle);
    }

    const ReferencesContext = struct {
        references: []Reference,
        aabbs: []AABB,
        triangles: [*]const IndexTriangle,
        vertices: *const VertexStream,

        pub fn run(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            const self = @intToPtr(*ReferencesContext, context);

            var bounds = math.aabb.empty;

            for (self.triangles[begin..end]) |t, i| {
                const a = self.vertices.position(t.i[0]);
                const b = self.vertices.position(t.i[1]);
                const c = self.vertices.position(t.i[2]);

                const min = tri.min(a, b, c);
                const max = tri.max(a, b, c);

                const r = i + begin;
                self.references[r].set(min, max, @intCast(u32, r));

                bounds.bounds[0] = @minimum(bounds.bounds[0], min);
                bounds.bounds[1] = @maximum(bounds.bounds[1], max);
            }

            self.aabbs[id] = bounds;
        }
    };

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

        var n = &tree.nodes[dest_node];
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
