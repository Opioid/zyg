const Base = @import("../bvh/builder_base.zig").Base;
const Reference = @import("../bvh/split_candidate.zig").Reference;
const Tree = @import("prop_tree.zig").Tree;

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
        const num_primitives = @as(u32, @intCast(indices.len));

        try self.super.reserve(alloc, num_primitives);

        if (0 == num_primitives) {
            try tree.allocateIndices(alloc, 0);
            _ = try tree.allocateNodes(alloc, 0);
            return;
        }

        var references = try alloc.alloc(Reference, num_primitives);

        var bounds = math.aabb.Empty;

        for (indices, 0..) |prop, i| {
            const b = aabbs[prop];

            references[i].set(b.bounds[0], b.bounds[1], prop);

            bounds.bounds[0] = math.min4(bounds.bounds[0], b.bounds[0]);
            bounds.bounds[1] = math.max4(bounds.bounds[1], b.bounds[1]);
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
        const node = self.super.kernel.build_nodes.items[source_node];
        var n = node;

        if (0 == node.numIndices()) {
            const child0 = self.super.currentNodeIndex();
            n.setSplitNode(child0);
            tree.nodes[dest_node] = n;

            self.super.newNode();
            self.super.newNode();

            const source_child0 = node.children();

            self.serialize(source_child0, child0, tree, current_prop);
            self.serialize(source_child0 + 1, child0 + 1, tree, current_prop);
        } else {
            var i = current_prop.*;
            const num = node.numIndices();
            n.setLeafNode(i, num);
            tree.nodes[dest_node] = n;

            const begin = node.children();
            const indices = self.super.kernel.reference_ids.items[begin .. begin + num];
            @memcpy(tree.indices[i .. i + num], indices);

            current_prop.* += num;
        }
    }
};
