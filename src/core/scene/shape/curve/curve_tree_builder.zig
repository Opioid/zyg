const Tree = @import("curve_tree.zig").Tree;
const CurveBuffer = @import("curve_buffer.zig").Buffer;
const crv = @import("curve.zig");
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
        curves: []const u32,
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

            @memcpy(references[cur..end], p.references.items);

            const cur32: u32 = @intCast(cur);
            for (references[cur..end]) |*r| {
                r.incrPrimitive(cur32);
            }

            @memcpy(reference_to_curve_map[cur..end], p.reference_to_curve_map.items);
            @memcpy(partitions[cur..end], p.partitions.items);

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
        self.serialize(0, 0, tree, reference_to_curve_map, partitions, &current_curve);
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

            const Self = @This();

            pub fn eval(self: *Self, cp: [4]Vec4f, width: Vec2f, ps: []const u8) void {
                var cost: f32 = 0.0;

                for (ps, 0..) |p, i| {
                    const partition = crv.partition(cp, p);

                    var box = crv.cubicBezierBounds(partition.cp);
                    const width0 = math.lerp(width[0], width[1], partition.u_range[0]);
                    const width1 = math.lerp(width[0], width[1], partition.u_range[1]);
                    box.expand(math.max(width0, width1) * 0.5);

                    self.aabbs[i] = box;
                    self.partitions[i] = p;

                    var mod: f32 = 1.0;

                    if (1 == p or 2 == p) {
                        mod = 2.0;
                    } else if (p >= 3 and p <= 6) {
                        mod = 4.0;
                    } else if (p >= 7 and p <= 14) {
                        mod = 8.0;
                    }

                    cost += mod * box.volume();
                }

                self.count = @as(u32, @intCast(ps.len));
                self.cost = cost;
            }

            pub fn swapLess(a: *Self, b: *Self) void {
                if (b.cost < a.cost) {
                    std.mem.swap(Self, a, b);
                }
            }
        };

        privates: []Private,
        curves: [*]const u32,
        vertices: *const CurveBuffer,
        alloc: Allocator,

        pub fn run(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            const self: *ReferencesContext = @ptrCast(@alignCast(context));

            var private = &self.privates[id];

            const len_estimate = (end - begin) * 4;

            private.references = List(Reference).initCapacity(self.alloc, len_estimate) catch return;
            private.reference_to_curve_map = List(u32).initCapacity(self.alloc, len_estimate) catch return;
            private.partitions = List(u8).initCapacity(self.alloc, len_estimate) catch return;

            var bounds = math.aabb.Empty;

            var ref_id: u32 = 0;

            for (begin..end) |i| {
                const curve = self.curves[i];

                const cp = self.vertices.curvePoints(curve);
                const width = self.vertices.curveWidth(curve);

                var candidate_a: PartitionCandidate = undefined;
                var candidate_b: PartitionCandidate = undefined;

                candidate_a.eval(cp, width, &.{0});
                candidate_b.eval(cp, width, &.{ 1, 2 });
                candidate_a.swapLess(&candidate_b);

                candidate_b.eval(cp, width, &.{ 3, 4, 2 });
                candidate_a.swapLess(&candidate_b);

                candidate_b.eval(cp, width, &.{ 1, 5, 6 });
                candidate_a.swapLess(&candidate_b);

                candidate_b.eval(cp, width, &.{ 3, 4, 5, 6 });
                candidate_a.swapLess(&candidate_b);

                candidate_b.eval(cp, width, &.{ 7, 8, 9, 10, 2 });
                candidate_a.swapLess(&candidate_b);

                candidate_b.eval(cp, width, &.{ 1, 11, 12, 13, 14 });
                candidate_a.swapLess(&candidate_b);

                candidate_b.eval(cp, width, &.{ 7, 8, 9, 10, 5, 6 });
                candidate_a.swapLess(&candidate_b);

                candidate_b.eval(cp, width, &.{ 3, 4, 11, 12, 13, 14 });
                candidate_a.swapLess(&candidate_b);

                candidate_b.eval(cp, width, &.{ 3, 9, 10, 11, 12, 6 });
                candidate_a.swapLess(&candidate_b);

                candidate_b.eval(cp, width, &.{ 7, 8, 4, 5, 13, 14 });
                candidate_a.swapLess(&candidate_b);

                candidate_b.eval(cp, width, &.{ 7, 8, 9, 10, 11, 12, 13, 14 });
                candidate_a.swapLess(&candidate_b);

                const partition = candidate_a;

                for (0..partition.count) |p| {
                    const box = partition.aabbs[p];

                    private.references.append(self.alloc, Reference.init(box, ref_id)) catch {};
                    private.reference_to_curve_map.append(self.alloc, curve) catch {};
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
        curves: []const u32,
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

            self.serialize(source_child0, child0, tree, curves, partitions, current_curve);
            self.serialize(source_child0 + 1, child0 + 1, tree, curves, partitions, current_curve);
        } else {
            var i = current_curve.*;

            tree.nodes[dest_node] = n;

            const begin = node.children();
            const end = begin + node.numIndices();

            for (begin..end) |p| {
                const ref = self.super.kernel.reference_ids.items[p];
                const curve = curves[ref];
                const partition = partitions[ref];
                tree.data.setCurve(i, curve, partition);

                i += 1;
            }

            current_curve.* = i;
        }
    }
};
