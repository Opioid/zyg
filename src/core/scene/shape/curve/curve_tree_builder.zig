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
const List = std.ArrayListUnmanaged;

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
            .privates = try alloc.alloc(ReferencesContext.Private, threads.numThreads()),
            .curves = curves.ptr,
            .vertices = &vertices,
            .alloc = alloc,
        };

        const num = threads.runRange(&context, ReferencesContext.run, 0, num_curves, @sizeOf(Reference));

        var num_references: u32 = 0;

        var bounds = math.aabb.Empty;
        for (context.privates[0..num]) |p| {
            num_references += @intCast(p.references.items.len);

            bounds.mergeAssign(p.aabb);
        }

        var references = try alloc.alloc(Reference, num_references);

        var reference_to_curve_map = try alloc.alloc(u32, num_references);
        defer alloc.free(reference_to_curve_map);

        var partitions = try alloc.alloc(u8, num_references);
        defer alloc.free(partitions);

        var cur: usize = 0;
        for (context.privates[0..num]) |p| {
            const len = p.references.items.len;
            const end = cur + len;

            std.mem.copy(Reference, references[cur..end], p.references.items);

            const cur32: u32 = @intCast(cur);
            for (references[cur..end]) |*r| {
                r.incrPrimitive(cur32);
            }

            std.mem.copy(u32, reference_to_curve_map[cur..end], p.reference_to_curve_map.items);
            std.mem.copy(u8, partitions[cur..end], p.partitions.items);

            cur += len;
        }

        for (context.privates[0..num]) |*p| {
            p.deinit(alloc);
        }

        alloc.free(context.privates);

        try self.super.split(alloc, references, bounds, threads);

        try tree.data.allocateCurves(alloc, self.super.numReferenceIds(), vertices);
        try tree.allocateNodes(alloc, self.super.numBuildNodes());

        var current_curve: u32 = 0;
        self.super.newNode();
        self.serialize(0, 0, tree, curves, reference_to_curve_map, partitions, &current_curve);
    }

    const ReferencesContext = struct {
        const Private = struct {
            references: List(Reference),
            reference_to_curve_map: List(u32),
            partitions: List(u8),
            aabb: AABB,

            pub fn deinit(self: *Private, alloc: Allocator) void {
                self.partitions.deinit(alloc);
                self.reference_to_curve_map.deinit(alloc);
                self.references.deinit(alloc);
            }
        };

        privates: []Private,
        curves: [*]const IndexCurve,
        vertices: *const CurveBuffer,
        alloc: Allocator,

        pub fn run(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            const self = @as(*ReferencesContext, @ptrCast(@alignCast(context)));

            var private = &self.privates[id];

            private.references = List(Reference).initCapacity(self.alloc, self.privates.len) catch return;
            private.reference_to_curve_map = List(u32).initCapacity(self.alloc, self.privates.len) catch return;
            private.partitions = List(u8).initCapacity(self.alloc, self.privates.len) catch return;

            var bounds = math.aabb.Empty;

            var ref_id: u32 = 0;

            for (begin..end) |i| {
                const index: u32 = @intCast(i);
                const curve = self.curves[i];

                const cp = self.vertices.curvePoints(curve.pos);
                const width = self.vertices.curveWidth(curve.width);

                var single_box = crv.cubicBezierBounds(cp);
                single_box.expand(math.max(width[0], width[1]) * 0.5);

                var quad_box = math.aabb.Empty;

                var box4_0: AABB = undefined;
                var box4_1: AABB = undefined;
                var box4_2: AABB = undefined;
                var box4_3: AABB = undefined;

                {
                    box4_0 = crv.cubicBezierBounds(crv.cubicBezierSubdivide4_0(cp));
                    const width1 = math.lerp(width[0], width[1], 0.25);
                    box4_0.expand(math.max(width[0], width1) * 0.5);

                    quad_box.mergeAssign(box4_0);
                }

                {
                    box4_1 = crv.cubicBezierBounds(crv.cubicBezierSubdivide4_1(cp));
                    const width0 = math.lerp(width[0], width[1], 0.25);
                    const width1 = math.lerp(width[0], width[1], 0.5);
                    box4_1.expand(math.max(width0, width1) * 0.5);

                    quad_box.mergeAssign(box4_1);
                }

                {
                    box4_2 = crv.cubicBezierBounds(crv.cubicBezierSubdivide4_2(cp));
                    const width0 = math.lerp(width[0], width[1], 0.5);
                    const width1 = math.lerp(width[0], width[1], 0.75);
                    box4_2.expand(math.max(width0, width1) * 0.5);

                    quad_box.mergeAssign(box4_2);
                }

                {
                    box4_3 = crv.cubicBezierBounds(crv.cubicBezierSubdivide4_3(cp));
                    const width0 = math.lerp(width[0], width[1], 0.75);
                    box4_3.expand(math.max(width0, width[1]) * 0.5);

                    quad_box.mergeAssign(box4_3);
                }

                const ratio = (box4_0.volume() + box4_1.volume() + box4_2.volume() + box4_3.volume()) / single_box.volume();
                if (ratio > 0.75) {
                    private.references.append(self.alloc, Reference.init(single_box, ref_id)) catch {};
                    private.reference_to_curve_map.append(self.alloc, index) catch {};
                    private.partitions.append(self.alloc, 0) catch {};
                    ref_id += 1;

                    bounds.mergeAssign(single_box);
                } else {
                    private.references.append(self.alloc, Reference.init(box4_0, ref_id)) catch {};
                    private.reference_to_curve_map.append(self.alloc, index) catch {};
                    private.partitions.append(self.alloc, 1) catch {};
                    ref_id += 1;

                    private.references.append(self.alloc, Reference.init(box4_1, ref_id)) catch {};
                    private.reference_to_curve_map.append(self.alloc, index) catch {};
                    private.partitions.append(self.alloc, 2) catch {};
                    ref_id += 1;

                    private.references.append(self.alloc, Reference.init(box4_2, ref_id)) catch {};
                    private.reference_to_curve_map.append(self.alloc, index) catch {};
                    private.partitions.append(self.alloc, 3) catch {};
                    ref_id += 1;

                    private.references.append(self.alloc, Reference.init(box4_3, ref_id)) catch {};
                    private.reference_to_curve_map.append(self.alloc, index) catch {};
                    private.partitions.append(self.alloc, 4) catch {};
                    ref_id += 1;

                    bounds.mergeAssign(quad_box);
                }
            }

            private.aabb = bounds;
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
