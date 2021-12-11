const Base = @import("../bvh/builder_base.zig").Base;
const Reference = @import("../bvh/split_candidate.zig").Reference;
const Tree = @import("tree.zig").Tree;
const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Builder = struct {
    super: Base,

    pub fn init(alloc: Allocator) !Builder {
        return Builder{ .super = try Base.init(alloc, 16, 64, 4) };
    }

    pub fn deinit(self: *Builder, alloc: Allocator) void {
        self.super.deinit(alloc);
    }

    pub fn build(
        self: *Builder,
        alloc: Allocator,
        tree: *Tree,
        indices: []const u32,
        aabbs: []const AABB,
        threads: *Threads,
    ) !void {
        const num_primitives = @intCast(u32, indices.len);

        try self.super.reserve(alloc, num_primitives);

        if (0 == num_primitives) {
            try tree.allocateIndices(alloc, 0);
            _ = try tree.allocateNodes(alloc, 0);
            return;
        }

        var references = try alloc.alloc(Reference, num_primitives);

        var bounds = math.aabb.empty;

        for (indices) |prop, i| {
            const b = aabbs[prop];

            references[i].set(b.bounds[0], b.bounds[1], prop);

            bounds.bounds[0] = @minimum(bounds.bounds[0], b.bounds[0]);
            bounds.bounds[1] = @maximum(bounds.bounds[1], b.bounds[1]);
        }

        try self.super.split(alloc, references, bounds, threads);

        try tree.allocateIndices(alloc, self.super.numReferenceIds());
        try tree.allocateNodes(alloc, self.super.numBuildNodes());

        var current_prop: u32 = 0;
        self.super.newNode();
        self.serialize(0, 0, tree, &current_prop);
    }

    fn serialize(
        self: *Builder,
        source_node: u32,
        dest_node: u32,
        tree: *Tree,
        current_prop: *u32,
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

            self.serialize(source_child0, child0, tree, current_prop);
            self.serialize(source_child0 + 1, child0 + 1, tree, current_prop);
        } else {
            var i = current_prop.*;
            const num = node.numIndices();
            n.setLeafNode(i, num);

            const begin = node.children();
            const indices = self.super.kernel.reference_ids.items[begin .. begin + num];
            std.mem.copy(u32, tree.indices[i .. i + num], indices);

            current_prop.* += num;
        }
    }
};
