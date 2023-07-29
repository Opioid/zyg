const Tree = @import("curve_tree.zig").Tree;
const CurveBuffer = @import("curve_buffer.zig").Buffer;
const crv = @import("curve.zig");
const IndexCurve = crv.IndexCurve;
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
        curves: []const IndexCurve,
        vertices: CurveBuffer,
        threads: *Threads,
    ) !void {
        const num_curves: u32 = @intCast(curves.len);

        var context = ReferencesContext{
            .references = try alloc.alloc(Reference, num_curves * 4),
            .reference_to_curve_map = try alloc.alloc(u32, num_curves * 4),
            .partitions = try alloc.alloc(u8, num_curves * 4),
            .aabbs = try alloc.alloc(AABB, threads.numThreads()),
            .curves = curves.ptr,
            .vertices = &vertices,
        };

        const num = threads.runRange(&context, ReferencesContext.run, 0, num_curves, @sizeOf(Reference));

        var bounds = math.aabb.Empty;
        for (context.aabbs[0..num]) |b| {
            bounds.mergeAssign(b);
        }

        alloc.free(context.aabbs);

        try self.super.split(alloc, context.references, bounds, threads);

        try tree.data.allocateCurves(alloc, self.super.numReferenceIds(), vertices);
        try tree.allocateNodes(alloc, self.super.numBuildNodes());

        var current_curve: u32 = 0;
        self.super.newNode();
        self.serialize(0, 0, tree, curves, context.reference_to_curve_map, context.partitions, &current_curve);

        alloc.free(context.partitions);
        alloc.free(context.reference_to_curve_map);
    }

    const ReferencesContext = struct {
        references: []Reference,
        reference_to_curve_map: []u32,
        partitions: []u8,
        aabbs: []AABB,
        curves: [*]const IndexCurve,
        vertices: *const CurveBuffer,

        pub fn run(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            const self = @as(*ReferencesContext, @ptrCast(@alignCast(context)));

            var bounds = math.aabb.Empty;

            for (begin..end) |i| {
                const index: u32 = @intCast(i);
                const curve = self.curves[i];

                const cp = self.vertices.curvePoints(curve.pos);
                const width = self.vertices.curveWidth(curve.width);

                {
                    var box = crv.cubicBezierBounds(crv.cubicBezierSubdivide4_0(cp));
                    const width1 = math.lerp(width[0], width[1], 0.25);
                    box.expand(math.max(width[0], width1) * 0.5);

                    const ref_id = index * 4 + 0;
                    self.references[ref_id].set(box.bounds[0], box.bounds[1], ref_id);
                    self.reference_to_curve_map[ref_id] = index;
                    self.partitions[ref_id] = 1;

                    bounds.mergeAssign(box);
                }

                {
                    var box = crv.cubicBezierBounds(crv.cubicBezierSubdivide4_1(cp));
                    const width0 = math.lerp(width[0], width[1], 0.25);
                    const width1 = math.lerp(width[0], width[1], 0.5);
                    box.expand(math.max(width0, width1) * 0.5);

                    const ref_id = index * 4 + 1;
                    self.references[ref_id].set(box.bounds[0], box.bounds[1], ref_id);
                    self.reference_to_curve_map[ref_id] = index;
                    self.partitions[ref_id] = 2;

                    bounds.mergeAssign(box);
                }

                {
                    var box = crv.cubicBezierBounds(crv.cubicBezierSubdivide4_2(cp));
                    const width0 = math.lerp(width[0], width[1], 0.5);
                    const width1 = math.lerp(width[0], width[1], 0.75);
                    box.expand(math.max(width0, width1) * 0.5);

                    const ref_id = index * 4 + 2;
                    self.references[ref_id].set(box.bounds[0], box.bounds[1], ref_id);
                    self.reference_to_curve_map[ref_id] = index;
                    self.partitions[ref_id] = 3;

                    bounds.mergeAssign(box);
                }

                {
                    var box = crv.cubicBezierBounds(crv.cubicBezierSubdivide4_3(cp));
                    const width0 = math.lerp(width[0], width[1], 0.75);
                    box.expand(math.max(width0, width[1]) * 0.5);

                    const ref_id = index * 4 + 3;
                    self.references[ref_id].set(box.bounds[0], box.bounds[1], ref_id);
                    self.reference_to_curve_map[ref_id] = index;
                    self.partitions[ref_id] = 4;

                    bounds.mergeAssign(box);
                }
            }

            self.aabbs[id] = bounds;
        }
    };

    fn serialize(
        self: *Builder,
        source_node: u32,
        dest_node: u32,
        tree: *Tree,
        curves: []const IndexCurve,
        reference_to_curve_map: []const u32,
        partitions: []const u8,
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

            self.serialize(source_child0, child0, tree, curves, reference_to_curve_map, partitions, current_curve);
            self.serialize(source_child0 + 1, child0 + 1, tree, curves, reference_to_curve_map, partitions, current_curve);
        } else {
            var i = current_curve.*;
            const num = node.numIndices();
            tree.nodes[dest_node] = n;

            const ro = node.children();

            var p = ro;
            var end = ro + num;

            while (p < end) : (p += 1) {
                const ref = self.super.kernel.reference_ids.items[p];
                const curve = curves[reference_to_curve_map[ref]];
                const partition = partitions[ref];
                tree.data.setCurve(i, curve, partition);

                i += 1;
            }

            current_curve.* = i;
        }
    }
};
