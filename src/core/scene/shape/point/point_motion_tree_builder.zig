const Base = @import("../../bvh/builder_base.zig").Base;
const spc = @import("../../bvh/split_candidate.zig");
const Reference = spc.Reference;
const References = spc.References;
const Tree = @import("point_motion_tree.zig").Tree;
const Scene = @import("../../scene.zig").Scene;

const base = @import("base");
const math = base.math;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;
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
        radius: f32,
        positions: [][]Pack3f,
        radii: [][]f32,
        threads: *Threads,
    ) !void {
        const num_frames: u32 = @truncate(positions.len);

        const num_primitives: u32 = @intCast(positions[0].len);

        // if (0 == num_primitives) {
        //     try tree.allocateIndices(alloc, 0);
        //     _ = try tree.allocateNodes(alloc, 0);
        //     return;
        // }

        const radiusv: Vec4f = @splat(radius);

        var references = try References.initCapacity(alloc, num_primitives);

        var bounds: AABB = .empty;

        for (0..num_primitives) |i| {
            var box: AABB = .empty;

            for (0..num_frames) |f| {
                const pos: Vec4f = math.vec3fTo4f(positions[f][i]);

                const r = if (radii.len > 0) @as(Vec4f, @splat(radii[f][i])) else radiusv;

                box.mergeAssign(AABB.init(pos - r, pos + r));
            }

            if (box.surfaceArea() > 0.0) {
                references.appendAssumeCapacity(Reference.init(box, @intCast(i)));
            }

            bounds.mergeAssign(box);
        }

        if (references.items.len > 0) {
            try self.super.split(alloc, try references.toOwnedSlice(alloc), bounds, threads);

            try tree.allocateIndices(alloc, self.super.numReferenceIds());
            try tree.allocateNodes(alloc, self.super.numBuildNodes());

            var current_prop: u32 = 0;
            self.super.newNode();
            self.serialize(0, 0, tree, &current_prop);
        }

        try tree.data.allocatePoints(alloc, radius, positions, radii);
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
            const i = current_prop.*;
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
