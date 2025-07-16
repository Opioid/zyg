const Tree = @import("triangle_tree.zig").Tree;
const MotionTree = @import("triangle_motion_tree.zig").Tree;
const tri = @import("triangle.zig");
const VertexBuffer = @import("vertex_buffer.zig").Buffer;
const Reference = @import("../../bvh/split_candidate.zig").Reference;
const Base = @import("../../bvh/builder_base.zig").Base;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Builder = struct {
    pub const IndexTriangle = struct {
        i: [3]u32,
        part: u32,
    };

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

        var bounds: AABB = .empty;
        for (context.aabbs[0..num]) |b| {
            bounds.mergeAssign(b);
        }

        alloc.free(context.aabbs);

        try self.super.split(alloc, context.references, bounds, threads);

        try tree.data.allocateTriangles(alloc, self.super.numReferenceIds(), vertices);
        try tree.allocateNodes(alloc, self.super.numBuildNodes());

        var current_triangle: u32 = 0;
        self.super.newNode();
        self.serialize(0, 0, tree, triangles, &current_triangle);
    }

    pub fn buildMotion(
        self: *Builder,
        alloc: Allocator,
        tree: *MotionTree,
        triangles: []const IndexTriangle,
        vertices: VertexBuffer,
        frame_duration: u64,
        start_frame: u32,
        threads: *Threads,
    ) !void {
        var context = ReferencesContext{
            .references = try alloc.alloc(Reference, triangles.len),
            .aabbs = try alloc.alloc(AABB, threads.numThreads()),
            .triangles = triangles.ptr,
            .vertices = &vertices,
        };

        const num = threads.runRange(&context, ReferencesContext.runMotion, 0, @intCast(triangles.len), @sizeOf(Reference));

        var bounds: AABB = .empty;
        for (context.aabbs[0..num]) |b| {
            bounds.mergeAssign(b);
        }

        alloc.free(context.aabbs);

        try self.super.split(alloc, context.references, bounds, threads);

        try tree.data.allocateTriangles(alloc, self.super.numReferenceIds(), vertices);
        try tree.allocateNodes(alloc, self.super.numBuildNodes());

        tree.data.frame_duration = @intCast(frame_duration);
        tree.data.start_frame = start_frame;

        var current_triangle: u32 = 0;
        self.super.newNode();
        self.serializeMotion(0, 0, tree, triangles, &current_triangle);
    }

    const ReferencesContext = struct {
        references: []Reference,
        aabbs: []AABB,
        triangles: [*]const IndexTriangle,
        vertices: *const VertexBuffer,

        pub fn run(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            const self: *ReferencesContext = @ptrCast(@alignCast(context));

            var bounds: AABB = .empty;

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

        pub fn runMotion(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            const self: *ReferencesContext = @ptrCast(@alignCast(context));

            const num_frames = self.vertices.numFrames();

            var bounds: AABB = .empty;

            for (self.triangles[begin..end], 0..) |t, i| {
                var min: Vec4f = @splat(std.math.floatMax(f32));
                var max: Vec4f = @splat(-std.math.floatMax(f32));

                for (0..num_frames) |f| {
                    const a = self.vertices.positionAt(f, t.i[0]);
                    const b = self.vertices.positionAt(f, t.i[1]);
                    const c = self.vertices.positionAt(f, t.i[2]);

                    min = math.min4(tri.min(a, b, c), min);
                    max = math.max4(tri.max(a, b, c), max);
                }

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

            self.serialize(source_child0, child0, tree, triangles, current_triangle);
            self.serialize(source_child0 + 1, child0 + 1, tree, triangles, current_triangle);
        } else {
            var i = current_triangle.*;

            tree.nodes[dest_node] = n;

            const begin = node.children();
            const end = begin + node.numIndices();

            for (begin..end) |p| {
                const t = triangles[self.super.kernel.reference_ids.items[p]];
                tree.data.setTriangle(i, t.i[0], t.i[1], t.i[2], t.part);

                i += 1;
            }

            current_triangle.* = i;
        }
    }

    fn serializeMotion(
        self: *Builder,
        source_node: u32,
        dest_node: u32,
        tree: *MotionTree,
        triangles: []const IndexTriangle,
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

            self.serializeMotion(source_child0, child0, tree, triangles, current_triangle);
            self.serializeMotion(source_child0 + 1, child0 + 1, tree, triangles, current_triangle);
        } else {
            var i = current_triangle.*;

            tree.nodes[dest_node] = n;

            const begin = node.children();
            const end = begin + node.numIndices();

            for (begin..end) |p| {
                const t = triangles[self.super.kernel.reference_ids.items[p]];
                tree.data.setTriangle(i, t.i[0], t.i[1], t.i[2], t.part);

                i += 1;
            }

            current_triangle.* = i;
        }
    }
};
