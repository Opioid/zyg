const Node = @import("node.zig").Node;
const spc = @import("split_candidate.zig");
const SplitCandidate = spc.SplitCandidate;
const Reference = spc.Reference;
const References = spc.References;
const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Threads = base.thread.Pool;
const ThreadContext = base.thread.Pool.Context;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Parallelize_threshold = 1024;

pub const Base = struct {
    num_slices: u32,
    sweep_threshold: u32,
    max_primitives: u32,
    spatial_split_threshold: u32,

    split_candidates: std.ArrayListUnmanaged(SplitCandidate),
    reference_ids: std.ArrayListUnmanaged(u32) = .{},
    build_nodes: std.ArrayListUnmanaged(Node) = .{},

    current_node: u32 = undefined,
    nodes: []Node = undefined,

    aabb_surface_area: f32 = undefined,
    references: []const Reference = undefined,

    pub fn init(
        alloc: *Allocator,
        num_slices: u32,
        sweep_threshold: u32,
        max_primitives: u32,
        spatial_split_threshold: u32,
    ) !Base {
        return Base{
            .num_slices = num_slices,
            .sweep_threshold = sweep_threshold,
            .max_primitives = max_primitives,
            .spatial_split_threshold = spatial_split_threshold,
            .split_candidates = try std.ArrayListUnmanaged(SplitCandidate).initCapacity(
                alloc,
                3 + std.math.max(3 * sweep_threshold, 3 * 2 * num_slices),
            ),
        };
    }

    pub fn deinit(self: *Base, alloc: *Allocator) void {
        self.split_candidates.deinit(alloc);
        self.reference_ids.deinit(alloc);
        self.build_nodes.deinit(alloc);
    }

    const SplitError = error{
        OutOfMemory,
    };

    pub fn split(
        self: *Base,
        alloc: *Allocator,
        node_id: u32,
        references: []const Reference,
        aabb: AABB,
        depth: u32,
        threads: *Threads,
    ) SplitError!void {
        defer alloc.free(references);

        var node = &self.build_nodes.items[node_id];
        node.setAABB(aabb);

        const num_primitives = @intCast(u32, references.len);
        if (num_primitives <= self.max_primitives) {
            try self.assign(alloc, node, references);
        } else {
            const spo = self.splittingPlane(references, aabb, depth, threads);
            if (spo) |sp| {
                if (num_primitives <= 0xFF and @intToFloat(f32, num_primitives) <= sp.cost) {
                    try self.assign(alloc, node, references);
                } else {
                    var references0: References = undefined;
                    var references1: References = undefined;
                    try sp.distribute(alloc, references, &references0, &references1);

                    if (num_primitives <= 0xFF and (0 == references0.items.len or 0 == references1.items.len)) {
                        // This can happen if we didn't find a good splitting plane.
                        // It means every triangle was (partially) on the same side of the plane.
                        try self.assign(alloc, node, references);
                    } else {
                        const child0 = @intCast(u32, self.build_nodes.items.len);

                        node.setSplitNode(child0, sp.axis);

                        try self.build_nodes.append(alloc, .{});
                        try self.build_nodes.append(alloc, .{});

                        const next_depth = depth + 1;
                        try self.split(alloc, child0, references0.toOwnedSlice(alloc), sp.aabbs[0], next_depth, threads);
                        try self.split(alloc, child0 + 1, references1.toOwnedSlice(alloc), sp.aabbs[1], next_depth, threads);
                    }
                }
            } else {
                if (num_primitives <= 0xFF) {
                    try self.assign(alloc, node, references);
                } else {
                    std.debug.print("Cannot split node further \n", .{});
                }
            }
        }
    }

    pub fn splittingPlane(self: *Base, references: []const Reference, aabb: AABB, depth: u32, threads: *Threads) ?SplitCandidate {
        const X = 0;
        const Y = 1;
        const Z = 2;

        self.split_candidates.clearRetainingCapacity();

        const num_references = @intCast(u32, references.len);

        const position = aabb.position();

        self.split_candidates.appendAssumeCapacity(SplitCandidate.init(X, position, true));
        self.split_candidates.appendAssumeCapacity(SplitCandidate.init(Y, position, true));
        self.split_candidates.appendAssumeCapacity(SplitCandidate.init(Z, position, true));

        if (num_references <= self.sweep_threshold) {
            for (references) |r| {
                const max = r.bound(1);
                self.split_candidates.appendAssumeCapacity(SplitCandidate.init(X, max, false));
                self.split_candidates.appendAssumeCapacity(SplitCandidate.init(Y, max, false));
                self.split_candidates.appendAssumeCapacity(SplitCandidate.init(Z, max, false));
            }
        } else {
            const extent = aabb.extent();
            const min = aabb.bounds[0];

            const la = extent.indexMaxComponent3();
            const step = extent.v[la] / @intToFloat(f32, self.num_slices);

            const ax = [_]u8{ 0, 1, 2 };
            for (ax) |a| {
                const extent_a = extent.v[a];
                const num_steps = @floatToInt(u32, std.math.ceil(extent_a / step));
                const step_a = extent_a / @intToFloat(f32, num_steps);

                var i: u32 = 1;
                while (i < num_steps) : (i += 1) {
                    const fi = @intToFloat(f32, i);

                    var slice = position;
                    slice.v[a] = min.v[a] + fi * step_a;
                    self.split_candidates.appendAssumeCapacity(SplitCandidate.init(a, slice, false));

                    if (depth < self.spatial_split_threshold) {
                        self.split_candidates.appendAssumeCapacity(SplitCandidate.init(a, slice, true));
                    }
                }
            }
        }

        const aabb_surface_area = aabb.surfaceArea();

        if (references.len < Parallelize_threshold) {
            for (self.split_candidates.items) |*sc| {
                sc.evaluate(references, aabb_surface_area);
            }
        } else {
            self.aabb_surface_area = aabb_surface_area;
            self.references = references;

            threads.runRange(self, evaluateRange, 0, @intCast(u32, self.split_candidates.items.len));
        }

        var sc: usize = 0;
        var min_cost = self.split_candidates.items[0].cost;

        for (self.split_candidates.items[1..]) |c, i| {
            const cost = c.cost;
            if (cost < min_cost) {
                sc = i + 1;
                min_cost = cost;
            }
        }

        const sp = self.split_candidates.items[sc];

        if ((sp.aabbs[0].equals(aabb) and num_references == sp.num_sides[0]) or (sp.aabbs[1].equals(aabb) and num_references == sp.num_sides[1])) {
            return null;
        }

        return sp;
    }

    fn evaluateRange(context: ThreadContext, id: u32, begin: u32, end: u32) void {
        _ = id;

        const self = @intToPtr(*Base, context);

        const aabb_surface_area = self.aabb_surface_area;
        const references = self.references;

        for (self.split_candidates.items[begin..end]) |*sc| {
            sc.evaluate(references, aabb_surface_area);
        }
    }

    pub fn assign(self: *Base, alloc: *Allocator, node: *Node, references: []const Reference) !void {
        const num_references = @intCast(u8, references.len);

        node.setLeafNode(@intCast(u32, self.reference_ids.items.len), num_references);

        for (references) |r| {
            try self.reference_ids.append(alloc, r.primitive());
        }
    }

    pub fn reserve(self: *Base, alloc: *Allocator, num_primitives: u32) !void {
        try self.build_nodes.ensureTotalCapacity(
            alloc,
            std.math.max((3 * num_primitives) / self.max_primitives, 1),
        );
        self.build_nodes.clearRetainingCapacity();
        try self.build_nodes.append(alloc, .{});

        try self.reference_ids.ensureTotalCapacity(
            alloc,
            (num_primitives * 12) / 10,
        );
        self.reference_ids.clearRetainingCapacity();

        self.current_node = 0;
    }

    pub fn newNode(self: *Base) void {
        self.current_node += 1;
    }

    pub fn currentNodeIndex(self: Base) u32 {
        return self.current_node;
    }
};
