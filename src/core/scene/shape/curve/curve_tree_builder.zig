const Tree = @import("curve_tree.zig").Tree;
const CurveBuffer = @import("curve_buffer.zig").Buffer;
const crv = @import("curve.zig");
const IndexCurve = crv.IndexCurve;
const Reference = @import("../../bvh/split_candidate.zig").Reference;
const Base = @import("../../bvh/builder_base.zig").Base;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
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

        const PartitionCandidate = struct {
            const Max = 8;

            cost: f32,
            count: u32,
            aabbs: [Max]AABB,
            partitions: [Max]u8,

            const Self = PartitionCandidate;

            pub fn setPartition(self: *Self, slot: u32, cp: [4]Vec4f, width: Vec2f, p: u8) void {
                const partition = crv.partition(cp, p);

                var box = crv.cubicBezierBounds(partition.cp);
                const width0 = math.lerp(width[0], width[1], partition.u_range[0]);
                const width1 = math.lerp(width[0], width[1], partition.u_range[1]);
                box.expand(math.max(width0, width1) * 0.5);

                self.aabbs[slot] = box;
                self.partitions[slot] = p;
            }

            pub fn eval(self: *Self, count: u32) void {
                var cost: f32 = 0.0;
                for (self.aabbs[0..count], self.partitions[0..count]) |b, p| {
                    var mod: f32 = 1.0;

                    if (1 == p or 2 == p) {
                        mod = 2.0;
                    } else if (p >= 3 and p <= 6) {
                        mod = 4.0;
                    } else if (p >= 7 and p <= 14) {
                        mod = 8.0;
                    }

                    cost += mod * b.volume();
                }

                self.count = count;
                self.cost = cost;
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

            var candidates: [10]PartitionCandidate = undefined;

            var bounds = math.aabb.Empty;

            var ref_id: u32 = 0;

            for (begin..end) |i| {
                const index: u32 = @intCast(i);
                const curve = self.curves[i];

                const cp = self.vertices.curvePoints(curve.pos);
                const width = self.vertices.curveWidth(curve.width);

                candidates[0].setPartition(0, cp, width, 0);
                candidates[0].eval(1);

                candidates[1].setPartition(0, cp, width, 1);
                candidates[1].setPartition(1, cp, width, 2);
                candidates[1].eval(2);

                candidates[2].setPartition(0, cp, width, 3);
                candidates[2].setPartition(1, cp, width, 4);
                candidates[2].setPartition(2, cp, width, 2);
                candidates[2].eval(3);

                candidates[3].setPartition(0, cp, width, 1);
                candidates[3].setPartition(1, cp, width, 5);
                candidates[3].setPartition(2, cp, width, 6);
                candidates[3].eval(3);

                candidates[4].setPartition(0, cp, width, 3);
                candidates[4].setPartition(1, cp, width, 4);
                candidates[4].setPartition(2, cp, width, 5);
                candidates[4].setPartition(3, cp, width, 6);
                candidates[4].eval(4);

                candidates[5].setPartition(0, cp, width, 7);
                candidates[5].setPartition(1, cp, width, 8);
                candidates[5].setPartition(2, cp, width, 9);
                candidates[5].setPartition(3, cp, width, 10);
                candidates[5].setPartition(4, cp, width, 2);
                candidates[5].eval(5);

                candidates[6].setPartition(0, cp, width, 1);
                candidates[6].setPartition(1, cp, width, 11);
                candidates[6].setPartition(2, cp, width, 12);
                candidates[6].setPartition(3, cp, width, 13);
                candidates[6].setPartition(4, cp, width, 14);
                candidates[6].eval(5);

                candidates[7].setPartition(0, cp, width, 3);
                candidates[7].setPartition(1, cp, width, 9);
                candidates[7].setPartition(2, cp, width, 10);
                candidates[7].setPartition(3, cp, width, 11);
                candidates[7].setPartition(4, cp, width, 12);
                candidates[7].setPartition(5, cp, width, 6);
                candidates[7].eval(6);

                candidates[8].setPartition(0, cp, width, 7);
                candidates[8].setPartition(1, cp, width, 8);
                candidates[8].setPartition(2, cp, width, 4);
                candidates[8].setPartition(3, cp, width, 5);
                candidates[8].setPartition(4, cp, width, 13);
                candidates[8].setPartition(5, cp, width, 14);
                candidates[8].eval(6);

                candidates[9].setPartition(0, cp, width, 7);
                candidates[9].setPartition(1, cp, width, 8);
                candidates[9].setPartition(2, cp, width, 9);
                candidates[9].setPartition(3, cp, width, 10);
                candidates[9].setPartition(4, cp, width, 11);
                candidates[9].setPartition(5, cp, width, 12);
                candidates[9].setPartition(6, cp, width, 13);
                candidates[9].setPartition(7, cp, width, 14);
                candidates[9].eval(8);

                var pc: usize = 0;
                var min_cost = candidates[0].cost;

                for (candidates[1..], 1..) |c, n| {
                    const cost = c.cost;
                    if (cost < min_cost) {
                        pc = n;
                        min_cost = cost;
                    }
                }

                const partition = candidates[pc];

                for (0..partition.count) |p| {
                    const box = partition.aabbs[p];

                    private.references.append(self.alloc, Reference.init(box, ref_id)) catch {};
                    private.reference_to_curve_map.append(self.alloc, index) catch {};
                    private.partitions.append(self.alloc, partition.partitions[p]) catch {};
                    ref_id += 1;
                    bounds.mergeAssign(box);
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
