const Tree = @import("triangle_tree.zig").Tree;
const tri = @import("triangle.zig");
const IndexTriangle = tri.IndexTriangle;
const VertexBuffer = @import("vertex_buffer.zig").Buffer;
const Reference = @import("../../bvh/split_candidate.zig").Reference;
const Base = @import("../../bvh/builder_base.zig").Base;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Builder = struct {
    super: Base,

    pub fn init(alloc: Allocator, num_slices: u32, sweep_threshold: u32, max_primitives: u32) !Builder {
        return Builder{ .super = try Base.init(alloc, num_slices, sweep_threshold, max_primitives) };
    }

    pub fn deinit(self: *Builder, alloc: Allocator) void {
        self.super.deinit(alloc);
    }

    pub fn build(
        self: *Builder,
        alloc: Allocator,
        tree: *Tree,
        triangles: []const IndexTriangle,
        vertices: VertexBuffer,
        threads: *Threads,
    ) !void {
        var context = ReferencesContext{
            .references = try alloc.alloc(Reference, triangles.len),
            .aabbs = try alloc.alloc(AABB, threads.numThreads()),
            .triangles = triangles.ptr,
            .vertices = &vertices,
        };

        const num = threads.runRange(&context, ReferencesContext.run, 0, @intCast(triangles.len), @sizeOf(Reference));

        var bounds = math.aabb.Empty;
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
        vertices: *const VertexBuffer,

        pub fn run(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            const self = @as(*ReferencesContext, @ptrCast(@alignCast(context)));

            var bounds = math.aabb.Empty;

            for (self.triangles[begin..end], 0..) |t, i| {
                const a = self.vertices.position(t.i[0]);
                const b = self.vertices.position(t.i[1]);
                const c = self.vertices.position(t.i[2]);

                const min = tri.min(a, b, c);
                const max = tri.max(a, b, c);

                const r = i + begin;
                self.references[r].set(min, max, @intCast(r));

                bounds.bounds[0] = math.min4(bounds.bounds[0], min);
                bounds.bounds[1] = math.max4(bounds.bounds[1], max);
            }

            self.aabbs[id] = bounds;
        }
    };

    fn serialize(
        self: *Builder,
        source_node: u32,
        dest_node: u32,
        tree: *Tree,
        triangles: []const IndexTriangle,
        vertices: VertexBuffer,
        current_triangle: *u32,
    ) void {
        const node = self.super.kernel.build_nodes.items[source_node];
        var n = node;

        if (0 == node.numIndices()) {
            const child0 = self.super.currentNodeIndex();
            n.setSplitNode(child0);
            tree.nodes[dest_node] = n;

            self.super.newNode();
            self.super.newNode();

            const source_child0 = node.children();

            self.serialize(source_child0, child0, tree, triangles, vertices, current_triangle);
            self.serialize(source_child0 + 1, child0 + 1, tree, triangles, vertices, current_triangle);
        } else {
            var i = current_triangle.*;

            tree.nodes[dest_node] = n;

            const begin = node.children();
            const end = begin + node.numIndices();

            for (begin..end) |p| {
                const t = triangles[self.super.kernel.reference_ids.items[p]];
                tree.data.setTriangle(i, t.i[0], t.i[1], t.i[2], t.part, vertices);

                i += 1;
            }

            current_triangle.* = i;
        }
    }
};
