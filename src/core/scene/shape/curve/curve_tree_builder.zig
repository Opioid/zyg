const Tree = @import("curve_tree.zig").Tree;
const CurveBuffer = @import("curve_buffer.zig").Buffer;
const curve = @import("curve.zig");
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

    pub fn build(self: *Builder, alloc: Allocator, tree: *Tree, curves: CurveBuffer, threads: *Threads) !void {
        const num_curves = curves.numCurves();

        try self.super.reserve(alloc, num_curves);

        var context = ReferencesContext{
            .references = try alloc.alloc(Reference, num_curves),
            .aabbs = try alloc.alloc(AABB, threads.numThreads()),
            .num_curves = num_curves,
            .curves = &curves,
        };

        const num = threads.runRange(&context, ReferencesContext.run, 0, num_curves, @sizeOf(Reference));

        var bounds = math.aabb.Empty;
        for (context.aabbs[0..num]) |b| {
            bounds.mergeAssign(b);
        }

        alloc.free(context.aabbs);

        try self.super.split(alloc, context.references, bounds, threads);

        try tree.data.allocateCurves(alloc, self.super.numReferenceIds(), num_curves, curves);
        try tree.allocateNodes(alloc, self.super.numBuildNodes());

        var current_curve: u32 = 0;
        self.super.newNode();
        self.serialize(0, 0, tree, curves, &current_curve);
    }

    const ReferencesContext = struct {
        references: []Reference,
        aabbs: []AABB,
        num_curves: u32,
        curves: *const CurveBuffer,

        pub fn run(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            const self = @as(*ReferencesContext, @ptrCast(@alignCast(context)));

            var bounds = math.aabb.Empty;

            for (begin..end) |i| {
                const index: u32 = @intCast(i);

                const cp = self.curves.curvePoints(index);
                const width = self.curves.curveWidth(index);

                var box = curve.cubicBezierBounds(cp);
                box.expand(math.max(width[0], width[1]) * 0.5);

                const min = box.bounds[0];
                const max = box.bounds[1];

                self.references[index].set(min, max, index);

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
        curves: CurveBuffer,
        current_curve: *u32,
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

            self.serialize(source_child0, child0, tree, curves, current_curve);
            self.serialize(source_child0 + 1, child0 + 1, tree, curves, current_curve);
        } else {
            var i = current_curve.*;
            const num = node.numIndices();
            tree.nodes[dest_node] = n;

            const ro = node.children();

            var p = ro;
            var end = ro + num;

            while (p < end) : (p += 1) {
                const c = self.super.kernel.reference_ids.items[p];
                tree.data.setCurve(i, c);

                i += 1;
            }

            current_curve.* = i;
        }
    }
};
